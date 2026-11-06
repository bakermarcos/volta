import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/race.dart';
import '../room/session.dart';
import 'track.dart';
import 'race_scene.dart';
import 'history.dart';
import 'victory.dart';

Route<T> _tvRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
);

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});
  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> with WidgetsBindingObserver {
  final _focus = FocusNode();
  final _lobbyFocus = FocusNode();
  final _keys = <LogicalKeyboardKey>{};
  final _missingSince = <String, double>{};
  Race? _race;
  Race? _lastRace;
  int _laps = 2;
  bool _turbo = false, _mirrored = false, _reversed = false;
  Circuit? _variant;
  Circuit get _track =>
      _variant ??= _circuit.variant(mirrored: _mirrored, reversed: _reversed);
  void _publishSettings() => SessionScope.read(context).configureRace(
    _laps,
    _circuit.name,
    turbo: _turbo,
    mirrored: _mirrored,
    reversed: _reversed,
  );
  bool _selectingCircuit = false;
  Timer? _resultsTimer;
  GlobalKey _sceneKey = GlobalKey();
  Timer? _pauseRequestTimer;
  bool _pauseArmed = false;
  Circuit _circuit = Circuit.catalog.firstWhere((c) => c.name == 'Brasil');
  String? _address;
  double _countdown = 0, _intro = 1;
  double _telemetryAt = 0;
  bool _submitted = false;
  bool _paused = false;
  int _startMs = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_revealFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusLobby());
  }

  void _revealFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || Scrollable.maybeOf(context) == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: .5,
      duration: const Duration(milliseconds: 120),
    );
  }

  void _focusLobby() {
    if (mounted && _race == null && _lobbyFocus.canRequestFocus) {
      _lobbyFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_revealFocus);
    WidgetsBinding.instance.removeObserver(this);
    _pauseRequestTimer?.cancel();
    _resultsTimer?.cancel();
    _focus.dispose();
    _lobbyFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _keys.clear();
      if (Platform.isAndroid &&
          _race != null &&
          !_race!.finished &&
          !_paused &&
          _countdown == 0) {
        _pause();
      }
    }
  }

  void _begin(List<Driver> drivers) {
    _resultsTimer?.cancel();
    _race = Race(
      drivers,
      circuit: _track,
      totalLaps: _laps,
      turbo: _turbo,
      mirrored: _mirrored,
      reversed: _reversed,
    );
    _countdown = 0;
    _intro = 0;
    _telemetryAt = 0;
    _submitted = false;
    _startMs = DateTime.now().millisecondsSinceEpoch;
    _missingSince.clear();
    _keys.clear();
    _focus.requestFocus();
  }

  void _advance(double seconds) {
    final dt = seconds.clamp(0.0, .05);
    final session = SessionScope.read(context).state;
    final room = session.room;
    if (!session.local && room?.status == 'countdown' && _race == null) {
      setState(() => _begin(room!.players.where((p) => p.connected).toList()));
    }
    if (!session.local &&
        room?.status == 'lobby' &&
        _race != null &&
        _countdown > 0) {
      setState(() {
        _race = null;
        _countdown = 0;
      });
      return;
    }
    final race = _race;
    if (race == null || race.finished) return;
    if (_intro < 1) {
      _intro = math.min(1, _intro + dt / 5);
      if (_intro == 1) {
        _countdown = 3;
        if (!session.local) SessionScope.read(context).start();
      }
      if (mounted) setState(() {});
      return;
    }
    if (room?.paused == true && !_paused) {
      _pause();
      return;
    }
    if (_paused) return;
    if (!session.local && room == null) {
      return;
    }
    if (_countdown > 0) {
      final previous = _countdown.ceil();
      _countdown = (_countdown - dt).clamp(0.0, 3.0);
      if (_countdown.ceil() != previous) {
        if (!session.local) {
          SessionScope.read(context).countdown(_countdown.ceil());
        }
        if (_countdown == 0) _startMs = DateTime.now().millisecondsSinceEpoch;
        setState(() {});
      }
    }
    final inputs = <String, ControlInput>{};
    if (session.local) {
      inputs['local-1'] = ControlInput(
        accelerate: _keys.contains(LogicalKeyboardKey.keyW),
        reverse: _keys.contains(LogicalKeyboardKey.keyS),
        boost: _keys.contains(LogicalKeyboardKey.shiftLeft),
        steer:
            (_keys.contains(LogicalKeyboardKey.keyD) ? 1 : 0) -
            (_keys.contains(LogicalKeyboardKey.keyA) ? 1 : 0),
      );
      inputs['local-2'] = ControlInput(
        accelerate: _keys.contains(LogicalKeyboardKey.arrowUp),
        reverse: _keys.contains(LogicalKeyboardKey.arrowDown),
        boost: _keys.contains(LogicalKeyboardKey.space),
        steer:
            (_keys.contains(LogicalKeyboardKey.arrowRight) ? 1 : 0) -
            (_keys.contains(LogicalKeyboardKey.arrowLeft) ? 1 : 0),
      );
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final car in race.cars) {
        final player = room!.players
            .where((p) => p.id == car.driver.id)
            .firstOrNull;
        if (player == null || !player.connected) {
          _missingSince.putIfAbsent(car.driver.id, () => race.elapsed);
          if (race.elapsed - _missingSince[car.driver.id]! > 15) {
            car.retired = true;
          }
          continue;
        }
        _missingSince.remove(car.driver.id);
        final data = room.inputs[car.driver.id] ?? {};
        final updated = (data['updatedAt'] as num?)?.toInt() ?? 0;
        if (updated < _startMs || now - updated > 1800) continue;
        inputs[car.driver.id] = ControlInput(
          accelerate: data['accelerate'] == true,
          reverse: data['reverse'] == true,
          boost: data['boost'] == true,
          steer: (data['steer'] as num?)?.toDouble() ?? 0,
        );
      }
    }
    final previousRemaining = race.finishingIn?.ceil();
    race.step(dt, inputs, hold: _countdown > 0);
    if (_countdown > 0) return;
    if (race.finishingIn?.ceil() != previousRemaining) setState(() {});
    if (!session.local && race.elapsed - _telemetryAt >= .2) {
      _telemetryAt = race.elapsed;
      SessionScope.read(context).telemetry(race);
    }
    if (race.finished && !_submitted) {
      setState(() => _submitted = true);
      SessionScope.read(context).finish(race);
      _resultsTimer = Timer(const Duration(seconds: 8), _rematch);
    }
  }

  void _keyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _requestPause();
      return;
    }
    if (event is KeyDownEvent) _keys.add(event.logicalKey);
    if (event is KeyUpEvent) _keys.remove(event.logicalKey);
  }

  void _requestPause() {
    if (_paused || _race == null || _race!.finished || _countdown > 0) return;
    if (_pauseArmed) {
      _pauseRequestTimer?.cancel();
      setState(() => _pauseArmed = false);
      _pause();
      return;
    }
    setState(() => _pauseArmed = true);
    _pauseRequestTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _pauseArmed = false);
    });
  }

  Future<void> _pause() async {
    if (_paused || _race == null || _race!.finished) return;
    _paused = true;
    _pauseRequestTimer?.cancel();
    _pauseArmed = false;
    SessionScope.read(context).setPaused(true);
    _keys.clear();
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Corrida pausada'),
        content: const Text('Os carros estão parados. Pronto para continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair da corrida'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _paused = false;
    SessionScope.read(context).setPaused(false);
    if (leave == true) {
      await SessionScope.read(context).leave();
    } else {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.watch(context).state;
    final room = session.room;
    final players = session.local
        ? [
            const Driver('local-1', 'Lima', 0, ready: true),
            if (session.localPlayers == 2)
              const Driver('local-2', 'Azul', 1, ready: true),
          ]
        : room?.players ?? <Driver>[];
    final connected = players.where((p) => p.connected).length;
    final race = _race;
    final tvMode = SessionScope.read(context).tvMode;
    if (race != null) {
      return KeyboardListener(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _keyEvent,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _requestPause();
          },
          child: Scaffold(
            body: SizedBox.expand(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: RaceScene(
                      key: _sceneKey,
                      race: race,
                      circuit: _track,
                      onAdvance: _advance,
                      approach: _intro < .8 ? 0 : (_intro - .8) / .2,
                      tvMode: tvMode,
                    ),
                  ),
                  if (_intro < 1 || _countdown > 0)
                    Text(
                      _intro < .8
                          ? 'Carregando a pista'
                          : _intro < 1
                          ? 'Está pronto?'
                          : '${_countdown.ceil()}',
                      style: TextStyle(
                        fontSize: _intro < 1 ? 36 : 96,
                        color: lime,
                        fontWeight: FontWeight.bold,
                        shadows: const [Shadow(color: ink, blurRadius: 12)],
                      ),
                    ),
                  if (race.finished)
                    _StopEdge(child: VictoryCelebration(child: _results(race))),
                  if (race.finishingIn != null && !race.finished)
                    Positioned(
                      bottom: 24,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ink,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Último piloto · ${race.finishingIn!.ceil()} s para terminar',
                            style: const TextStyle(color: lime, fontSize: 20),
                          ),
                        ),
                      ),
                    ),
                  if (!race.finished)
                    Positioned(
                      top: MediaQuery.sizeOf(context).height * .05,
                      left: MediaQuery.sizeOf(context).width / 2 - 85,
                      child: FilledButton.tonalIcon(
                        onPressed: _intro < 1 || _countdown > 0
                            ? null
                            : _requestPause,
                        icon: const Icon(Icons.pause),
                        label: Text(_pauseArmed ? 'Confirmar pausa' : 'Pausar'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return KeyboardListener(
      focusNode: _focus,
      onKeyEvent: _keyEvent,
      child: _StopEdge(
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width * .045,
                vertical: MediaQuery.sizeOf(context).height * .04,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const VoltaMark(height: 34),
                      const Spacer(),
                      if (!Platform.isAndroid)
                        TextButton(
                          onPressed: SessionScope.read(context).toggleTvMode,
                          child: Text(tvMode ? 'Sair do modo TV' : 'Modo TV'),
                        ),
                      TextButton(
                        onPressed: () => showRaceHistory(context),
                        child: const Text('Histórico'),
                      ),
                      TextButton(
                        onPressed: () => SessionScope.read(context).leave(),
                        child: const Text('Sair'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final menu = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 120,
                                  height: 68,
                                  child: CustomPaint(
                                    painter: CircuitThumbnail(
                                      _track,
                                      color: lime,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(
                                  child: Text(
                                    'Próxima corrida',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      height: 1.15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 136),
                              child: Text(
                                '$_laps voltas${_turbo ? ' · Turbo' : ''}${_reversed ? ' · Inverso' : ''}${_mirrored ? ' · Espelhado' : ''}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  color: muted,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              focusNode: _lobbyFocus,
                              onPressed: _selectCircuit,
                              icon: const Icon(Icons.route),
                              label: Text(
                                _circuit.name,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _settings,
                              icon: const Icon(Icons.tune),
                              label: const Text('Configurações'),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed:
                                  connected >= 1 &&
                                      (session.local || room?.canStart == true)
                                  ? () {
                                      if (session.local) {
                                        setState(() => _begin(players));
                                      } else {
                                        setState(
                                          () => _begin(
                                            players
                                                .where((p) => p.connected)
                                                .toList(),
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                              icon: const Icon(Icons.sports_score),
                              label: const Text('Largar  →'),
                            ),
                            const SizedBox(height: 16),
                            if (session.error != null)
                              Text(
                                session.error!,
                                style: const TextStyle(color: Colors.orange),
                              ),
                          ],
                        );
                        final preview = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: 1.7,
                              child: TickerMode(
                                enabled: !_selectingCircuit,
                                child: RaceScene(
                                  key: _sceneKey,
                                  circuit: _track,
                                  onAdvance: _advance,
                                  tvMode: tvMode,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _circuit.name,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              players.isEmpty
                                  ? 'Conecte os celulares pelo QR.'
                                  : '${players.where((p) => p.connected && p.ready).length}/$connected pilotos prontos',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final player in players)
                                  Chip(
                                    avatar: Icon(
                                      player.ready && player.connected
                                          ? Icons.check_circle
                                          : Icons.hourglass_top,
                                      color: Color(player.color),
                                      size: 22,
                                    ),
                                    label: Text(
                                      player.name,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                        if (constraints.maxWidth < 800) {
                          return ListView(
                            children: [
                              menu,
                              const SizedBox(height: 24),
                              preview,
                              const SizedBox(height: 24),
                              _sidebar(session, players, connected),
                            ],
                          );
                        }
                        if (constraints.maxWidth < 1100) {
                          return FocusTraversalGroup(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(child: menu),
                                ),
                                const SizedBox(width: 24),
                                SizedBox(
                                  width: 340,
                                  child: SingleChildScrollView(
                                    child: _sidebar(
                                      session,
                                      players,
                                      connected,
                                      showPlayers: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return FocusTraversalGroup(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 4,
                                child: SingleChildScrollView(child: menu),
                              ),
                              const SizedBox(width: 32),
                              Expanded(
                                flex: 5,
                                child: SingleChildScrollView(child: preview),
                              ),
                              const SizedBox(width: 24),
                              SizedBox(
                                width: 280,
                                child: SingleChildScrollView(
                                  child: _sidebar(session, players, connected),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _settings() async {
    final session = SessionScope.read(context);
    final settings = await Navigator.push<_RaceSettings>(
      context,
      _tvRoute(
        (_) => _RaceSettingsScreen(
          initial: _RaceSettings(
            laps: _laps,
            turbo: _turbo,
            mirrored: _mirrored,
            reversed: _reversed,
            localPlayers: session.state.localPlayers,
          ),
          local: session.state.local,
        ),
      ),
    );
    if (!mounted) return;
    _focusLobby();
    if (settings == null) return;
    setState(() {
      _laps = settings.laps;
      _turbo = settings.turbo;
      if (_mirrored != settings.mirrored || _reversed != settings.reversed) {
        _mirrored = settings.mirrored;
        _reversed = settings.reversed;
        _variant = null;
        _sceneKey = GlobalKey();
      }
    });
    if (session.state.local &&
        session.state.localPlayers != settings.localPlayers) {
      session.local(players: settings.localPlayers);
    }
    _publishSettings();
  }

  Future<void> _selectCircuit() async {
    setState(() => _selectingCircuit = true);
    final chosen = await Navigator.push<Circuit>(
      context,
      _tvRoute((_) => _CircuitScreen(initial: _circuit)),
    );
    if (!mounted) return;
    setState(() {
      _selectingCircuit = false;
      if (chosen != null && chosen != _circuit) {
        _circuit = chosen;
        _variant = null;
        _sceneKey = GlobalKey();
      }
    });
    _focusLobby();
    _publishSettings();
  }

  Widget _sidebar(
    SessionState session,
    List<Driver> players,
    int connected, {
    bool showPlayers = false,
  }) {
    final race = _race;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            session.local ? 'TECLADO' : 'CONECTAR CELULARES',
            style: const TextStyle(
              color: muted,
              letterSpacing: 2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          if (race == null && !session.local) ...[
            Row(
              children: [
                RoomQr(_address ?? session.addresses.first, size: 124),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeFocus(
                        child: SelectableText(
                          session.code!,
                          style: const TextStyle(
                            fontSize: 24,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Escaneie com a câmera.\nUse o mesmo Wi-Fi.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (session.addresses.length > 1)
              DropdownButton<String>(
                isExpanded: true,
                value: _address ?? session.addresses.first,
                items: [
                  for (final address in session.addresses)
                    DropdownMenuItem(
                      value: address,
                      child: Text(Uri.parse(address).host),
                    ),
                ],
                onChanged: (address) => setState(() => _address = address),
              ),
            ExcludeFocus(
              child: SelectableText(
                _address ?? session.addresses.first,
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ),
            const SizedBox(height: 12),
            if (players.any((p) => !p.connected))
              TextButton(
                onPressed: SessionScope.read(context).removeDisconnected,
                child: const Text('Remover desconectados'),
              ),
          ],
          if (players.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Esperando os primeiros pilotos…',
                style: TextStyle(color: muted),
              ),
            ),
          if (players.isNotEmpty && showPlayers)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final player in players)
                  Chip(
                    avatar: Icon(
                      player.ready && player.connected
                          ? Icons.check_circle
                          : Icons.hourglass_top,
                      color: Color(player.color),
                      size: 18,
                    ),
                    label: Text(player.name),
                  ),
              ],
            ),
          if (_lastRace != null) ...[
            const Divider(height: 32),
            const Text(
              'ÚLTIMO PLACAR',
              style: TextStyle(color: lime, fontWeight: FontWeight.bold),
            ),
            for (final car in _lastRace!.standings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_lastRace!.standings.indexOf(car) + 1}. ${car.driver.name} · ${car.finishedAt == null ? 'NÃO CONCLUIU' : formatRaceTime(car.finishedAt!)}',
                ),
              ),
          ],
          const SizedBox(height: 24),
          if (race?.finished == true)
            FilledButton(
              onPressed: session.busy
                  ? null
                  : () async {
                      if (!session.local) {
                        SessionScope.read(context).reset();
                      }
                      if (mounted &&
                          (session.local ||
                              SessionScope.read(context).state.error == null)) {
                        setState(() => _race = null);
                      }
                    },
              child: const Text('Voltar ao lobby  →'),
            ),
          if (race?.finished == true && session.error != null && !session.local)
            TextButton(
              onPressed: () => SessionScope.read(context).finish(race!),
              child: const Text('Atualizar resultado'),
            ),
          if (session.local) ...[
            const SizedBox(height: 16),
            const Text(
              'LIMA · W/S acelerar e ré · A/D virar · Shift boost\nAZUL · ↑/↓ acelerar e ré · ←/→ virar · Espaço boost',
              style: TextStyle(color: muted, fontSize: 12, height: 1.7),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _rematch() async {
    final session = SessionScope.read(context);
    await session.finish(_race!);
    if (!mounted) return;
    session.reset();
    _resultsTimer?.cancel();
    setState(() {
      _lastRace = _race;
      _race = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusLobby());
  }

  Widget _results(Race race) => Container(
    width: 400,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: ink.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: lime),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .9,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag_rounded, color: lime, size: 32),
          const SizedBox(height: 12),
          Text(
            race.standings.first.finishedAt == null
                ? 'CORRIDA ENCERRADA'
                : '${race.standings.first.driver.name} VENCEU!',
            style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < race.standings.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text('${i + 1}.', style: const TextStyle(color: lime)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(race.standings[i].driver.name)),
                  Text(
                    race.standings[i].retired
                        ? 'NÃO CONCLUIU'
                        : '${formatRaceTime(race.standings[i].finishedAt!)}\nMelhor ${race.standings[i].bestLap == null ? '—' : formatRaceTime(race.standings[i].bestLap!)}',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          for (final car in race.standings)
            if (car.lapTimes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${car.driver.name} · voltas ${car.lapTimes.map(formatRaceTime).join(' / ')}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
          const SizedBox(height: 16),
          FilledButton(
            autofocus: true,
            onPressed: _rematch,
            child: const Text('Voltar ao lobby  →'),
          ),
          TextButton(
            onPressed: () => showRaceHistory(context),
            child: const Text('Ver histórico'),
          ),
        ],
      ),
    ),
  );
}

class _StopEdge extends StatefulWidget {
  const _StopEdge({required this.child});
  final Widget child;

  @override
  State<_StopEdge> createState() => _StopEdgeState();
}

class _StopEdgeState extends State<_StopEdge> {
  final _scope = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.stop,
  );

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: _scope, child: widget.child);
}

class _RaceSettings {
  const _RaceSettings({
    required this.laps,
    required this.turbo,
    required this.mirrored,
    required this.reversed,
    required this.localPlayers,
  });

  final int laps, localPlayers;
  final bool turbo, mirrored, reversed;
}

class _RaceSettingsScreen extends StatefulWidget {
  const _RaceSettingsScreen({required this.initial, required this.local});
  final _RaceSettings initial;
  final bool local;

  @override
  State<_RaceSettingsScreen> createState() => _RaceSettingsScreenState();
}

class _RaceSettingsScreenState extends State<_RaceSettingsScreen> {
  late int laps = widget.initial.laps;
  late int localPlayers = widget.initial.localPlayers;
  late bool turbo = widget.initial.turbo;
  late bool mirrored = widget.initial.mirrored;
  late bool reversed = widget.initial.reversed;

  @override
  Widget build(BuildContext context) => _StopEdge(
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        leading: Focus(
          autofocus: true,
          child: IconButton(
            tooltip: 'Voltar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.chevron_left),
          ),
        ),
        title: const Text('Configurações da corrida'),
      ),
      body: SafeArea(
        child: FocusTraversalGroup(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Voltas', style: TextStyle(fontSize: 22)),
                        ),
                        IconButton.outlined(
                          tooltip: 'Diminuir voltas',
                          onPressed: laps > 1
                              ? () => setState(() => laps--)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(
                            '$laps',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton.outlined(
                          tooltip: 'Aumentar voltas',
                          onPressed: laps < 10
                              ? () => setState(() => laps++)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Modo turbo'),
                      subtitle: const Text('Karts 40% mais rápidos'),
                      value: turbo,
                      onChanged: (value) => setState(() => turbo = value),
                    ),
                    SwitchListTile(
                      title: const Text('Sentido inverso'),
                      subtitle: const Text('Corra no sentido contrário'),
                      value: reversed,
                      onChanged: (value) => setState(() => reversed = value),
                    ),
                    SwitchListTile(
                      title: const Text('Espelhar traçado'),
                      subtitle: const Text(
                        'Troque curvas à esquerda e à direita',
                      ),
                      value: mirrored,
                      onChanged: (value) => setState(() => mirrored = value),
                    ),
                    if (widget.local) ...[
                      const SizedBox(height: 12),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1 piloto')),
                          ButtonSegment(value: 2, label: Text('2 pilotos')),
                        ],
                        selected: {localPlayers},
                        onSelectionChanged: (value) =>
                            setState(() => localPlayers = value.single),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _RaceSettings(
                          laps: laps,
                          turbo: turbo,
                          mirrored: mirrored,
                          reversed: reversed,
                          localPlayers: localPlayers,
                        ),
                      ),
                      child: const Text('Aplicar configurações'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CircuitScreen extends StatefulWidget {
  const _CircuitScreen({required this.initial});
  final Circuit initial;

  @override
  State<_CircuitScreen> createState() => _CircuitScreenState();
}

class _CircuitScreenState extends State<_CircuitScreen> {
  late Circuit selected = widget.initial;

  @override
  Widget build(BuildContext context) => _StopEdge(
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left),
        ),
        title: Text('Pistas · ${selected.name}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('Usar pista'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: GridView.builder(
          key: const Key('circuit-grid'),
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.sizeOf(context).width < 800 ? 3 : 5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.45,
          ),
          itemCount: Circuit.catalog.length,
          itemBuilder: (context, index) {
            final track = Circuit.catalog[index];
            final active = selected == track;
            return OutlinedButton(
              autofocus: track == widget.initial,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(10),
                backgroundColor: active ? lime.withValues(alpha: .12) : panel,
              ),
              onPressed: () => Navigator.pop(context, track),
              child: Column(
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: CircuitThumbnail(
                        track,
                        color: active ? lime : muted,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}
