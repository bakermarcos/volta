import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/race.dart';
import 'room_service.dart';
import 'race_history.dart';
import 'browser_platform.dart';

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
  RoomHost? _service;
  StreamSubscription<RoomSnapshot>? _room;
  bool tvMode = false;
  bool onHome = false;
  String? selectedAddress;
  Future<void> toggleTvMode() async {
    tvMode = !tvMode;
    notifyListeners();
    if (kIsWeb) {
      try {
        await setBrowserFullscreen(tvMode);
      } catch (_) {
        tvMode = !tvMode;
        notifyListeners();
      }
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
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

  void home() {
    if (state.local) {
      final existing = _service;
      _set(
        existing == null
            ? const SessionState()
            : SessionState(
                room: existing.snapshot,
                code: existing.code,
                addresses: existing.addresses,
              ),
        notify: false,
      );
    }
    onHome = true;
    notifyListeners();
  }

  void local({int players = 1, bool timeTrial = false}) {
    onHome = false;
    _set(
      SessionState(local: true, localPlayers: players, timeTrial: timeTrial),
    );
  }

  Future<void> open({bool timeTrial = false}) async {
    if (state.busy) return;
    onHome = false;
    final existing = _service;
    if (existing != null) {
      _set(
        SessionState(
          timeTrial: timeTrial,
          room: existing.snapshot,
          code: existing.code,
          addresses: existing.addresses,
        ),
      );
      return;
    }
    _set(SessionState(busy: true, timeTrial: timeTrial));
    try {
      final service = kIsWeb
          ? await connectBrowserRoom()
          : await _openLocalRoom();
      _service = service;
      if (kIsWeb) {
        await ready;
        syncBrowserHistory(service, history.snapshot);
      }
      _room = service.changes.listen((room) {
        if (!service.connected) {
          _service = null;
          _room?.cancel();
          service.dispose();
          if (!state.local) {
            onHome = true;
            _set(
              const SessionState(
                error: 'A conexão com o servidor foi encerrada.',
              ),
            );
          }
          return;
        }
        if (state.local) return;
        _set(
          SessionState(
            timeTrial: state.timeTrial,
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
        );
      });
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

  Future<RoomService> _openLocalRoom() async {
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
    try {
      await service.create();
      return service;
    } catch (_) {
      await service.dispose();
      rethrow;
    }
  }

  void configureRace(
    int laps,
    String track, {
    bool turbo = false,
    bool mirrored = false,
    bool reversed = false,
  }) {
    if (state.local) return;
    _service?.configure(
      laps: laps,
      track: track,
      turbo: turbo,
      mirrored: mirrored,
      reversed: reversed,
    );
  }

  List<Driver>? start() {
    final service = _service;
    if (service == null || !service.start()) return null;
    return service.snapshot.players.where((p) => p.connected).toList();
  }

  void countdown(int value) => _service?.advanceCountdown(value);
  void setPaused(bool value) => _service?.setPaused(value);
  bool takeItemRequest(String id) => _service?.takeItemRequest(id) ?? false;
  void telemetry(Race race) => _service?.telemetry(race);
  Future<void> finish(Race race) {
    if (!race.finished) return Future.value();
    return _recorded[race] ??= _finish(race, state.local ? null : _service);
  }

  Future<void> _finish(Race race, RoomHost? service) async {
    await ready;
    try {
      await history.record(race);
      historyError = null;
    } catch (_) {
      historyError = 'Resultado disponível nesta sessão, mas não foi salvo neste aparelho.';
    }
    if (service != null && identical(service, _service)) {
      if (kIsWeb) syncBrowserHistory(service, history.snapshot);
      service.finish(race);
    }
    notifyListeners();
  }

  void replay() => _service?.replay();
  void reset() {
    if (!state.local) _service?.reset();
  }

  void removeDisconnected() => _service?.removeDisconnected();
  Future<void> leave() async {
    await _room?.cancel();
    await _service?.dispose();
    _service = null;
    selectedAddress = null;
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
