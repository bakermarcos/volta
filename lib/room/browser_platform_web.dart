import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../game/race.dart';
import 'room_service.dart';

const _historyKey = 'volta.races.v1';

String? _hostKey;

void initializeBrowserPlatform() {
  final fragment = Uri.base.fragment;
  if (fragment.startsWith('host=')) {
    _hostKey = fragment.substring(5);
  }
}

bool get canHostBrowserRoom => _hostKey != null;

String? readBrowserHistory() => web.window.localStorage.getItem(_historyKey);
void writeBrowserHistory(String contents) =>
    web.window.localStorage.setItem(_historyKey, contents);

Future<void> setBrowserFullscreen(bool enabled) async {
  if (enabled) {
    await web.document.documentElement?.requestFullscreen().toDart;
  } else if (web.document.fullscreenElement != null) {
    await web.document.exitFullscreen().toDart;
  }
}

void syncBrowserHistory(RoomHost room, Map<String, Object> history) {
  if (room is! _BrowserRoom) return;
  room._send({
    'type': 'history',
    'races': (history['races'] as List).take(20).toList(),
    'leaders': (history['leaders'] as List).take(50).toList(),
  });
}

Future<RoomHost> connectBrowserRoom() async {
  final page = Uri.base;
  final endpoint = Uri(
    scheme: page.scheme == 'https' ? 'wss' : 'ws',
    host: page.host,
    port: page.port,
    path: '/volta-host',
  );
  final socket = web.WebSocket(endpoint.toString());
  final room = _BrowserRoom(socket);
  try {
    socket.onopen = ((web.Event _) {
      room._send({'type': 'host', 'key': _hostKey});
    }).toJS;
    return await room._ready.future.timeout(const Duration(seconds: 5));
  } catch (_) {
    await room.dispose();
    rethrow;
  }
}

class _BrowserRoom implements RoomHost {
  _BrowserRoom(this._socket) {
    _socket.onmessage = ((web.MessageEvent event) {
      final message =
          jsonDecode((event.data as JSString).toDart) as Map<String, dynamic>;
      code = message['code'] as String;
      addresses = [Uri.base.resolve('/$code').toString()];
      final data = message['room'] as Map<String, dynamic>;
      final clockOffset =
          DateTime.now().millisecondsSinceEpoch - (message['sentAt'] as int);
      snapshot = RoomSnapshot(
        status: data['status'] as String,
        countdown: data['countdown'] as int,
        paused: data['paused'] as bool,
        totalLaps: data['totalLaps'] as int,
        circuit: data['circuit'] as String,
        turbo: data['turbo'] as bool,
        mirrored: data['mirrored'] as bool,
        reversed: data['reversed'] as bool,
        players: [
          for (final player in data['players'] as List)
            Driver(
              player['id'] as String,
              player['name'] as String,
              player['slot'] as int,
              connected: player['connected'] as bool,
              ready: player['ready'] as bool,
              colorIndex: player['colorIndex'] as int,
              model: player['model'] as int,
            ),
        ],
        inputs: {
          for (final entry in (data['inputs'] as Map).entries)
            entry.key as String: {
              ...Map<String, Object>.from(entry.value as Map),
              'updatedAt': (entry.value['updatedAt'] as int) + clockOffset,
            },
        },
        results: {
          for (final entry in (data['results'] as Map).entries)
            entry.key as String: Map<String, Object>.from(entry.value as Map),
        },
      );
      _requests.addAll((message['items'] as List).cast<String>());
      if (!changesController.isClosed) changesController.add(snapshot);
      if (!_ready.isCompleted) _ready.complete(this);
    }).toJS;
    _socket.onclose = ((web.Event _) {
      if (!_ready.isCompleted) {
        _ready.completeError(StateError('Relay connection closed'));
      }
      snapshot = const RoomSnapshot();
      _requests.clear();
      if (!changesController.isClosed) changesController.add(snapshot);
    }).toJS;
  }

  final web.WebSocket _socket;
  @override
  bool get connected => _socket.readyState == 1;
  final _ready = Completer<RoomHost>();
  final changesController = StreamController<RoomSnapshot>.broadcast();
  final _requests = <String>{};
  @override
  RoomSnapshot snapshot = const RoomSnapshot();
  @override
  String code = '';
  @override
  List<String> addresses = const [];
  @override
  Stream<RoomSnapshot> get changes => changesController.stream;

  void _send(Map<String, Object?> data) {
    if (_socket.readyState == 1) _socket.send(jsonEncode(data).toJS);
  }

  @override
  void configure({
    required int laps,
    required String track,
    required bool turbo,
    required bool mirrored,
    required bool reversed,
  }) => _send({
    'type': 'configure',
    'laps': laps,
    'track': track,
    'turbo': turbo,
    'mirrored': mirrored,
    'reversed': reversed,
  });

  @override
  bool start() {
    _send({'type': 'start'});
    return false; // The race starts when the relay confirms the countdown.
  }

  @override
  void advanceCountdown(int value) =>
      _send({'type': 'countdown', 'value': value});
  @override
  void setPaused(bool value) {
    _requests.clear();
    _send({'type': 'pause', 'value': value});
  }

  @override
  bool takeItemRequest(String id) => _requests.remove(id);
  @override
  void telemetry(Race race) =>
      _send({'type': 'telemetry', 'data': raceTelemetry(race)});
  @override
  void finish(Race race) =>
      _send({'type': 'finish', 'data': raceResults(race)});
  @override
  void replay() {
    _requests.clear();
    _send({'type': 'replay'});
  }

  @override
  void reset() {
    _requests.clear();
    _send({'type': 'reset'});
  }

  @override
  void removeDisconnected() => _send({'type': 'removeDisconnected'});
  @override
  Future<void> dispose() async {
    _socket.onclose = null;
    _socket.onmessage = null;
    _socket.close();
    await changesController.close();
  }
}
