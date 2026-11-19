import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:volta/room/room_service.dart';

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8765 : int.tryParse(args.singleOrNull ?? '');
  if (port == null || port < 1 || port > 65535) {
    stderr.writeln('Usage: dart run tool/serve_web.dart [port]');
    exitCode = 1;
    return;
  }
  final build = Directory('build/web');
  if (!File('${build.path}/index.html').existsSync()) {
    stderr.writeln('Build Volta first with flutter build web.');
    exitCode = 1;
    return;
  }

  final random = Random.secure();
  final key = List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  late final RoomService room;
  final assets = Directory('${build.path}/assets/assets');
  WebSocket? host;
  var history = <String, Object>{'races': [], 'leaders': []};

  void sendSnapshot(WebSocket socket, RoomSnapshot state) {
    if (socket.readyState != WebSocket.open) return;
    socket.add(
      jsonEncode({
        'code': room.code,
        'sentAt': DateTime.now().millisecondsSinceEpoch,
        'items': [
          for (final player in state.players)
            if (room.takeItemRequest(player.id)) player.id,
        ],
        'room': {
          'status': state.status,
          'countdown': state.countdown,
          'paused': state.paused,
          'totalLaps': state.totalLaps,
          'circuit': state.circuit,
          'turbo': state.turbo,
          'mirrored': state.mirrored,
          'reversed': state.reversed,
          'players': [
            for (final player in state.players)
              {
                'id': player.id,
                'name': player.name,
                'slot': player.slot,
                'ready': player.ready,
                'connected': player.connected,
                'colorIndex': player.paletteIndex,
                'model': player.model,
              },
          ],
          'inputs': state.inputs,
          'results': state.results,
        },
      }),
    );
  }

  Future<bool> handleHost(HttpRequest request) async {
    final expectedOrigin = request.requestedUri.origin;
    if (!WebSocketTransformer.isUpgradeRequest(request) ||
        request.headers.value('origin') != expectedOrigin) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return true;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final timeout = Timer(const Duration(seconds: 5), () {
      if (host != socket) socket.close();
    });
    socket.listen(
      (raw) {
        if (raw is! String || raw.length > 131072) {
          socket.close();
          return;
        }
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          if (host != socket) {
            if (host != null || data['type'] != 'host' || data['key'] != key) {
              socket.close();
              return;
            }
            host = socket;
            timeout.cancel();
            sendSnapshot(socket, room.snapshot);
            return;
          }
          switch (data['type']) {
            case 'history':
              history = {
                'races': data['races'] as List,
                'leaders': data['leaders'] as List,
              };
            case 'configure':
              room.configure(
                laps: data['laps'] as int,
                track: data['track'] as String,
                turbo: data['turbo'] as bool,
                mirrored: data['mirrored'] as bool,
                reversed: data['reversed'] as bool,
              );
            case 'start':
              room.start();
            case 'countdown':
              room.advanceCountdown(data['value'] as int);
            case 'pause':
              room.setPaused(data['value'] as bool);
            case 'telemetry':
              if (room.status == 'racing' && !room.paused) {
                room.sendTelemetry({
                  for (final entry in (data['data'] as Map).entries)
                    entry.key as String: Map<String, Object?>.from(
                      entry.value as Map,
                    ),
                });
              }
            case 'finish':
              if (room.status != 'racing') return;
              room.finishWithResults({
                for (final entry in (data['data'] as Map).entries)
                  entry.key as String: Map<String, Object>.from(
                    entry.value as Map,
                  ),
              });
            case 'replay':
              room.replay();
            case 'reset':
              room.reset();
            case 'removeDisconnected':
              room.removeDisconnected();
          }
        } on FormatException {
          socket.close();
        } on TypeError {
          socket.close();
        }
      },
      onDone: () {
        timeout.cancel();
        if (host == socket) {
          host = null;
          room.reset();
        }
      },
      onError: (Object _) {
        socket.close();
      },
    );
    return true;
  }

  room = RoomService(
    await File('${assets.path}/controller.html').readAsString(),
    kartModel: await File('${assets.path}/karts/kart_low_poly.glb')
        .readAsBytes(),
    characterModel: await File('${assets.path}/karts/kart-oobi.glb')
        .readAsBytes(),
    history: () => history,
    handleExtraRequest: (request) async {
      if (request.uri.path == '/volta-host') return handleHost(request);
      if (request.method != 'GET') return false;
      final segments = request.uri.pathSegments.where(
        (part) => part.isNotEmpty,
      );
      if (segments.any(
        (part) =>
            part == '.' ||
            part == '..' ||
            part.contains('/') ||
            part.contains('\\'),
      )) {
        return false;
      }
      final path = segments.isEmpty ? 'index.html' : segments.join('/');
      final file = File('${build.path}/$path');
      if (!await file.exists()) return false;
      request.response.headers.contentType = switch (path.split('.').last) {
        'html' => ContentType.html,
        'js' || 'mjs' => ContentType('text', 'javascript'),
        'json' => ContentType.json,
        'wasm' => ContentType('application', 'wasm'),
        'png' => ContentType('image', 'png'),
        'svg' => ContentType('image', 'svg+xml'),
        'css' => ContentType('text', 'css'),
        _ => ContentType.binary,
      };
      request.response.headers.set('referrer-policy', 'no-referrer');
      await request.response.addStream(file.openRead());
      await request.response.close();
      return true;
    },
  );
  await room.create(port: port);
  room.changes.listen((state) {
    final browser = host;
    if (browser != null) sendSnapshot(browser, state);
  });
  stdout.writeln('Open one of these private host URLs in the race browser.');
  stdout.writeln('Use the same Wi-Fi address for the browser and phones.');
  for (final address in room.addresses) {
    stdout.writeln(
      Uri.parse(address).replace(path: '/', fragment: 'host=$key'),
    );
  }
}
