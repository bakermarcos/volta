import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../game/race.dart';

class RoomSnapshot {
  const RoomSnapshot({
    this.status = 'lobby',
    this.countdown = 0,
    this.paused = false,
    this.totalLaps = 2,
    this.circuit = 'Brasil',
    this.turbo = false,
    this.mirrored = false,
    this.reversed = false,
    this.players = const [],
    this.inputs = const {},
    this.results = const {},
  });
  final String status;
  final int countdown, totalLaps;
  final String circuit;
  final bool paused, turbo, mirrored, reversed;
  bool get canStart =>
      status == 'lobby' &&
      players.any((p) => p.connected) &&
      players.where((p) => p.connected).every((p) => p.ready);
  final List<Driver> players;
  final Map<String, Map<String, Object>> inputs, results;
}

class RoomService {
  RoomService(
    this.controllerHtml, {
    this.history,
    this.httpsDirectory,
    this.kartModel = const [],
  });
  final Directory? httpsDirectory;
  HttpServer? _secureServer;
  final Map<String, Object> Function()? history;
  final String controllerHtml;
  final List<int> kartModel;
  final _changes = StreamController<RoomSnapshot>.broadcast();
  final _players = <String, Driver>{};
  final _sockets = <String, WebSocket>{};
  final _inputs = <String, Map<String, Object>>{};
  final _results = <String, Map<String, Object>>{};
  final _random = Random.secure();
  HttpServer? _server;
  String status = 'lobby';
  int countdown = 0;
  bool paused = false;
  int totalLaps = 2;
  String circuit = 'Brasil';
  bool turbo = false, mirrored = false, reversed = false;
  final _lastResults = <String, Map<String, Object>>{};
  final _pauseRequests = <String, DateTime>{};
  bool _closed = false;
  String code = '';
  List<String> addresses = [];
  RoomSnapshot get snapshot => RoomSnapshot(
    status: status,
    countdown: countdown,
    paused: paused,
    totalLaps: totalLaps,
    circuit: circuit,
    turbo: turbo,
    mirrored: mirrored,
    reversed: reversed,
    players: _players.values.toList()..sort((a, b) => a.slot.compareTo(b.slot)),
    inputs: Map.of(_inputs),
    results: Map.of(_results),
  );
  Stream<RoomSnapshot> get changes => _changes.stream;
  String _token(int length) => List.generate(
    length,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void> create({InternetAddress? address, int port = 0}) async {
    code = _token(4).toUpperCase();
    _server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    interfaces.sort(
      (a, b) => (a.name.startsWith('en') ? 0 : 1).compareTo(
        b.name.startsWith('en') ? 0 : 1,
      ),
    );
    addresses = [
      for (final interface in interfaces)
        for (final ip in interface.addresses)
          'http://${ip.address}:${_server!.port}/$code',
    ];
    if (addresses.isEmpty || address?.isLoopback == true) {
      addresses = ['http://127.0.0.1:${_server!.port}/$code'];
    }
    final directory = httpsDirectory;
    if (directory != null &&
        await File('${directory.path}/chain.pem').exists()) {
      final context = SecurityContext()
        ..useCertificateChain('${directory.path}/chain.pem')
        ..usePrivateKey('${directory.path}/server.key');
      _secureServer = await HttpServer.bindSecure(
        address ?? InternetAddress.anyIPv4,
        0,
        context,
      );
      _secureServer!.listen(_handle, onError: (Object error) {});
    }
    _server!.listen(_handle, onError: (Object error) {});
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path == '/room/$code' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = const Duration(seconds: 3);
      _accept(socket);
      return;
    }
    request.response.headers.set('Cache-Control', 'no-store');
    if (request.method == 'GET' &&
        request.uri.path == '/$code/volta-ca.cer' &&
        _secureServer != null) {
      request.response.headers.contentType = ContentType(
        'application',
        'x-x509-ca-cert',
      );
      request.response.add(
        await File('${httpsDirectory!.path}/volta-ca.cer').readAsBytes(),
      );
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/$code/iphone') {
      final secure = _secureServer;
      final url = secure == null
          ? ''
          : Uri(
              scheme: 'https',
              host: request.requestedUri.host,
              port: secure.port,
              path: '/$code',
            ).toString();
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Inclinação no iPhone · Volta</title><style>body{font:18px system-ui;background:#111918;color:#f1f4ee;max-width:600px;margin:40px auto;padding:24px;line-height:1.6}a{color:#bdfe55}li{margin:20px 0}</style><h1>Inclinação no iPhone</h1>${secure == null ? '<p>HTTPS ainda não foi preparado neste aparelho. O controle por toque funciona normalmente.</p>' : '<p>Este certificado pertence ao seu Mac. Instale apenas se esta for a sua sala na sua rede Wi-Fi.</p><ol><li><a href="/$code/volta-ca.cer">Baixar certificado Volta Wi-Fi Local CA</a> pelo Safari.</li><li>Abra Ajustes → Geral → VPN e Gerenciamento de Dispositivo e instale o perfil baixado.</li><li>Abra Ajustes → Geral → Sobre → Ajustes de Confiança de Certificado. Ative confiança total para Volta Wi-Fi Local CA.</li><li><a href="$url">Abrir controle HTTPS</a>, entre na sala e toque em Usar inclinação nos ajustes do controle.</li></ol><p>Se houver aviso de certificado, confira instalação e confiança antes de continuar. Mudou o IP do Mac? Gere novamente o certificado no Mac e reabra a sala.</p><p>Para remover, apague o perfil nos Ajustes.</p>'}<p><a href="/$code">Voltar ao controle por toque</a></p></html>''',
      );
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/$code/kart.glb') {
      request.response.headers.contentType = ContentType(
        'model',
        'gltf-binary',
      );
      request.response.add(kartModel);
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/$code/history') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          history?.call() ?? {'races': <Object>[], 'leaders': <Object>[]},
        ),
      );
      await request.response.close();
      return;
    }
    if (request.method != 'GET' || request.uri.path != '/$code') {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        controllerHtml.replaceAll('__IPHONE_GUIDE__', '/$code/iphone'),
      );
    }
    await request.response.close();
  }

  void _accept(WebSocket socket) {
    String? id;
    final deadline = Timer(const Duration(seconds: 5), () {
      if (id == null) socket.close();
    });
    void reject(String message) {
      socket.add(jsonEncode({'type': 'error', 'message': message}));
      socket.close();
    }

    socket.listen(
      (Object? raw) {
        if (raw is! String || raw.length > 1024) {
          socket.close();
          return;
        }
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) return;
          if (id == null) {
            if (decoded['type'] != 'join' || decoded['name'] is! String) return;
            final name = (decoded['name'] as String).trim();
            if (name.isEmpty || name.length > 16) {
              reject('Use um nome de até 16 letras.');
              return;
            }
            final token = decoded['token'];
            if (token is String && _players.containsKey(token)) {
              id = token;
              _sockets[id]?.close();
              final old = _players[id]!;
              _players[id!] = Driver(id!, name, old.slot);
              _cancelCountdown();
            } else {
              if (status != 'lobby') {
                reject('A corrida já começou. Aguarde a próxima.');
                return;
              }
              final occupied = _players.values.map((p) => p.slot).toSet();
              final slot = List.generate(
                maxPlayers,
                (i) => i,
              ).where((i) => !occupied.contains(i)).firstOrNull;
              if (slot == null) {
                reject('Sala cheia. Máximo de $maxPlayers pilotos.');
                return;
              }
              id = _token(16);
              _players[id!] = Driver(id!, name, slot);
            }
            deadline.cancel();
            _sockets[id!] = socket;
            socket.add(
              jsonEncode({
                'type': 'welcome',
                'token': id,
                'color': _players[id]!.color,
              }),
            );
            _publish();
            return;
          }
          if (decoded['type'] == 'ready' &&
              status == 'lobby' &&
              decoded['ready'] is bool) {
            final player = _players[id]!;
            _players[id!] = Driver(
              player.id,
              player.name,
              player.slot,
              ready: decoded['ready'] as bool,
            );
            _publish();
            return;
          }
          if (decoded['type'] == 'pause' && status == 'racing' && !paused) {
            final now = DateTime.now();
            final requested = _pauseRequests.remove(id);
            if (requested != null &&
                now.difference(requested) < const Duration(seconds: 4)) {
              setPaused(true);
            } else {
              _pauseRequests[id!] = now;
              socket.add(jsonEncode({'type': 'pauseRequest', 'armed': true}));
            }
            return;
          }
          if (decoded['type'] == 'leave') {
            _players.remove(id);
            _inputs.remove(id);
            _sockets.remove(id);
            _pauseRequests.remove(id);
            _cancelCountdown();
            socket.close();
            _publish();
            return;
          }
          if (decoded['type'] == 'ping') {
            socket.add(
              jsonEncode({'type': 'pong', 'sentAt': decoded['sentAt']}),
            );
            return;
          }
          if (decoded['type'] != 'input' || status != 'racing' || paused) {
            return;
          }
          final accelerate = decoded['accelerate'];
          final steer = decoded['steer'];
          if (accelerate is! bool ||
              steer is! num ||
              !steer.isFinite ||
              steer < -1 ||
              steer > 1) {
            return;
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          final previous = _inputs[id]?['updatedAt'] as int? ?? 0;
          if (now - previous < 25) return;
          _inputs[id!] = {
            'accelerate': accelerate,
            'reverse': decoded['reverse'] == true,
            'boost': decoded['boost'] == true,
            'steer': steer,
            'updatedAt': now,
          };
          if (!_closed) _changes.add(snapshot);
        } on FormatException {
          socket.close();
        }
      },
      onDone: () {
        deadline.cancel();
        if (id == null || _sockets[id] != socket) return;
        _sockets.remove(id);
        _inputs.remove(id);
        _pauseRequests.remove(id);
        final old = _players[id];
        if (old != null) {
          _players[id!] = Driver(old.id, old.name, old.slot, connected: false);
        }
        _cancelCountdown();
        _publish();
      },
      onError: (Object error) {
        socket.close();
      },
    );
  }

  void _publish() {
    if (_closed) return;
    _changes.add(snapshot);
    for (final entry in _sockets.entries) {
      entry.value.add(
        jsonEncode({
          'type': 'state',
          'status': status,
          'countdown': countdown,
          'paused': paused,
          'totalLaps': totalLaps,
          'circuit': circuit,
          'turbo': turbo,
          'mirrored': mirrored,
          'reversed': reversed,
          'lastResult': _lastResults[entry.key],
          'ready': _players[entry.key]?.ready ?? false,
          'readyCount': _players.values
              .where((p) => p.connected && p.ready)
              .length,
          'playerCount': _players.values.where((p) => p.connected).length,
          'result': _results[entry.key],
        }),
      );
    }
  }

  void configure({
    required int laps,
    required String track,
    bool turbo = false,
    bool mirrored = false,
    bool reversed = false,
  }) {
    if (status != 'lobby' ||
        laps < 1 ||
        laps > 10 ||
        (laps == totalLaps &&
            track == circuit &&
            turbo == this.turbo &&
            mirrored == this.mirrored &&
            reversed == this.reversed)) {
      return;
    }
    totalLaps = laps;
    circuit = track;
    this.turbo = turbo;
    this.mirrored = mirrored;
    this.reversed = reversed;
    for (final p in _players.values.toList()) {
      _players[p.id] = Driver(p.id, p.name, p.slot, connected: p.connected);
    }
    _publish();
  }

  void start() {
    if (!snapshot.canStart) return;
    status = 'countdown';
    countdown = 3;
    paused = false;
    _pauseRequests.clear();
    _results.clear();
    _inputs.clear();
    _publish();
  }

  void advanceCountdown(int value) {
    if (status != 'countdown' || value >= countdown) return;
    countdown = value.clamp(0, 3);
    if (countdown == 0) status = 'racing';
    _publish();
  }

  void _cancelCountdown() {
    if (status != 'countdown') return;
    status = 'lobby';
    countdown = 0;
    for (final p in _players.values.toList()) {
      _players[p.id] = Driver(p.id, p.name, p.slot, connected: p.connected);
    }
  }

  void setPaused(bool value) {
    if (status != 'racing' || paused == value) return;
    paused = value;
    _pauseRequests.clear();
    _inputs.clear();
    _publish();
  }

  void telemetry(Race race) {
    final standings = race.standings;
    for (final car in race.cars) {
      _sockets[car.driver.id]?.add(
        jsonEncode({
          'type': 'telemetry',
          'speed': car.speed.round(),
          'charge': car.boostCharge,
          'boosting': car.boosting,
          'lap': car.laps,
          'totalLaps': race.totalLaps,
          'wrongWay': () {
            final track = race.circuit.heading(car.trackAngle);
            final delta = atan2(
              sin(car.heading - track),
              cos(car.heading - track),
            );
            return delta.abs() > pi / 2 && car.speed.abs() > 30;
          }(),
          'finishingIn': race.finishingIn,
          'rank': standings.indexOf(car) + 1,
          'raceTime': car.raceTime(race.elapsed),
          'lapTime': car.lapTime(race.elapsed),
          if (car.bestLap != null) 'bestLap': car.bestLap!,
        }),
      );
    }
  }

  void finish(Race race) {
    status = 'finished';
    paused = false;
    final standings = race.standings;
    for (var i = 0; i < standings.length; i++) {
      final car = standings[i];
      _results[car.driver.id] = {
        'rank': i + 1,
        'time': car.finishedAt ?? 0,
        'retired': car.retired,
        'laps': car.lapTimes,
        if (car.bestLap != null) 'bestLap': car.bestLap!,
      };
    }
    _lastResults
      ..clear()
      ..addAll(_results);
    _publish();
  }

  void replay() {
    status = 'countdown';
    countdown = 3;
    paused = false;
    _pauseRequests.clear();
    _results.clear();
    _inputs.clear();
    _publish();
  }

  void reset() {
    status = 'lobby';
    countdown = 0;
    paused = false;
    _pauseRequests.clear();
    for (final p in _players.values.toList()) {
      _players[p.id] = Driver(p.id, p.name, p.slot, connected: p.connected);
    }
    _inputs.clear();
    _results.clear();
    _players.removeWhere((id, player) => !player.connected);
    _publish();
  }

  void removeDisconnected() {
    if (status != 'lobby') return;
    _players.removeWhere((id, player) => !player.connected);
    _publish();
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    for (final socket in _sockets.values.toList()) {
      await socket.close();
    }
    _sockets.clear();
    await _server?.close(force: true);
    await _secureServer?.close(force: true);
    await _changes.close();
  }
}
