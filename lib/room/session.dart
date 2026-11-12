import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/race.dart';
import 'room_service.dart';
import 'race_history.dart';

class SessionState {
  const SessionState({
    this.busy = false,
    this.local = false,
    this.timeTrial = false,
    this.localPlayers = 1,
    this.room,
    this.code,
    this.addresses = const [],
    this.error,
  });
  final bool busy, local, timeTrial;
  final int localPlayers;
  final RoomSnapshot? room;
  final String? code, error;
  final List<String> addresses;
  bool get active => local || code != null;
}

class Session extends ChangeNotifier {
  Session({RaceHistory? history}) : history = history ?? RaceHistory() {
    ready = _loadHistory();
  }
  final RaceHistory history;
  late final Future<void> ready;
  final _recorded = Expando<Future<void>>();
  String? historyError;
  Future<void> _loadHistory() async {
    try {
      await history.load();
    } catch (_) {
      historyError = 'Não foi possível ler o histórico local.';
    }
  }

  SessionState state = const SessionState();
  RoomService? _service;
  StreamSubscription<RoomSnapshot>? _room;
  bool tvMode = false;
  Future<void> toggleTvMode() async {
    tvMode = !tvMode;
    notifyListeners();
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        await const MethodChannel('volta/window')
            .invokeMethod<void>('fullscreen', tvMode);
      } on MissingPluginException {
        /* Widget tests do not have a native window. */
      }
    }
  }

  void _set(SessionState value, {bool notify = true}) {
    state = value;
    if (notify) notifyListeners();
  }

  void local({int players = 1, bool timeTrial = false}) => _set(
    SessionState(local: true, localPlayers: players, timeTrial: timeTrial),
  );
  Future<void> open({bool timeTrial = false}) async {
    _set(SessionState(busy: true, timeTrial: timeTrial));
    try {
      final html = await rootBundle.loadString('assets/controller.html');
      final kart = await rootBundle.load('assets/karts/kart_low_poly.glb');
      final character = await rootBundle.load('assets/karts/kart-oobi.glb');
      await ready;
      final service = RoomService(
        html,
        kartModel: kart.buffer.asUint8List(),
        characterModel: character.buffer.asUint8List(),
        history: () => history.snapshot,
        httpsDirectory: Directory('${history.file.parent.path}/https'),
      );
      _service = service;
      await service.create();
      _room = service.changes.listen(
        (room) => _set(
          SessionState(
            timeTrial: timeTrial,
            room: room,
            code: service.code,
            addresses: service.addresses,
          ),
          notify:
              room.status != state.room?.status ||
              room.countdown != state.room?.countdown ||
              room.paused != state.room?.paused ||
              room.totalLaps != state.room?.totalLaps ||
              room.circuit != state.room?.circuit ||
              room.turbo != state.room?.turbo ||
              room.mirrored != state.room?.mirrored ||
              room.reversed != state.room?.reversed ||
              !listEquals(room.players, state.room?.players) ||
              !mapEquals(room.results, state.room?.results),
        ),
      );
      _set(
        SessionState(
          timeTrial: timeTrial,
          room: service.snapshot,
          code: service.code,
          addresses: service.addresses,
        ),
      );
    } catch (error) {
      await _service?.dispose();
      _service = null;
      _set(SessionState(error: 'Não foi possível abrir a sala local: $error'));
    }
  }

  void configureRace(
    int laps,
    String track, {
    bool turbo = false,
    bool mirrored = false,
    bool reversed = false,
  }) => _service?.configure(
    laps: laps,
    track: track,
    turbo: turbo,
    mirrored: mirrored,
    reversed: reversed,
  );
  void start() => _service?.start();
  void countdown(int value) => _service?.advanceCountdown(value);
  void setPaused(bool value) => _service?.setPaused(value);
  void telemetry(Race race) => _service?.telemetry(race);
  Future<void> finish(Race race) {
    if (!race.finished) return Future.value();
    return _recorded[race] ??= _finish(race);
  }

  Future<void> _finish(Race race) async {
    await ready;
    try {
      await history.record(race);
      historyError = null;
    } catch (_) {
      historyError = 'Resultado disponível nesta sessão, mas não foi salvo neste aparelho.';
    }
    _service?.finish(race);
    notifyListeners();
  }

  void replay() => _service?.replay();
  void reset() => _service?.reset();
  void removeDisconnected() => _service?.removeDisconnected();
  Future<void> leave() async {
    await _room?.cancel();
    await _service?.dispose();
    _service = null;
    _set(const SessionState());
  }

  @override
  void dispose() {
    _room?.cancel();
    _service?.dispose();
    super.dispose();
  }
}

class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({
    super.key,
    required Session session,
    required super.child,
  }) : super(notifier: session);
  static Session watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;
  static Session read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<SessionScope>()!.widget
              as SessionScope)
          .notifier!;
}
