import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';

import '../game/race.dart';

class RaceAudio {
  bool _music = true;
  bool get music => _music;
  set music(bool value) {
    _music = value;
    _run(
      () =>
          _activeMusic()?.setVolume(value ? _musicLevel : 0) ?? Future.value(),
    );
  }

  final _speed = <String, double>{};
  AudioPlayer? _musicPlayer;
  AudioPlayer? _raceMusic;
  AudioPlayer? _engine;
  AudioPlayer? _skid;
  AudioPlayer? _rocket;
  final _shots = <AudioPlayer>[];
  var _shot = 0;
  var _track = '';
  var _musicLevel = 0.0;
  var _live = false;
  var _paused = false;
  var _closed = false;
  var _busy = false;
  var _again = false;
  var _mixAt = 0.0;
  var _hitAt = 1.0;
  var _engineLevel = -1.0;
  var _skidLevel = -1.0;
  var _rocketLevel = -1.0;
  var _launch = 0.0;

  void menu() {
    _live = false;
    _launch = 0;
    _run(_shareSpeakers);
    _run(_quietCars);
    _loop('audio/menu.m4a', .4);
    _run(_warmCars);
    _run(_warmRaceMusic);
  }

  void race() {
    _live = true;
    _paused = false;
    _speed.clear();
    _run(_startEngine);
    _loop('audio/race.m4a', .18);
    _run(_warmCars);
  }

  void climax() {
    _live = true;
    if (music) _once('audio/final_lap.m4a', .4);
    _loop('audio/climax.m4a', .2);
  }

  void win() {
    _live = false;
    _run(() async {
      await _quietCars();
      await _musicPlayer?.stop();
      await _raceMusic?.pause();
      _track = '';
      if (_music) await _playShot('audio/win.m4a', .85);
    });
  }

  Future<void> _quietCars() async {
    final engine = _engine;
    if (engine != null) {
      await engine.setVolume(0);
      await engine.pause();
      _engineLevel = -1;
    }
    final skid = _skid;
    if (skid != null) {
      await skid.setVolume(0);
      await skid.pause();
      _skidLevel = -1;
    }
    final rocket = _rocket;
    if (rocket != null) {
      await rocket.setVolume(0);
      await rocket.pause();
      _rocketLevel = -1;
    }
  }

  void count(int value) =>
      _once(value == 0 ? 'audio/go.m4a' : 'audio/beep.m4a', .7);

  void pause() {
    _paused = true;
    _run(() async {
      await _musicPlayer?.pause();
      await _raceMusic?.pause();
      await _engine?.pause();
      await _skid?.pause();
      await _rocket?.pause();
    });
  }

  void resume() {
    _paused = false;
    _run(() async {
      if (_track.isNotEmpty) await _activeMusic()?.resume();
      if (_live) {
        await _engine?.resume();
        await _skid?.resume();
        await _rocket?.resume();
      }
    });
  }

  void drive(Race race, double dt, {required bool hold}) {
    if (!_live || _paused || _closed) return;
    var speed = 0.0;
    var slip = 0.0;
    var launch = 0.0;
    var boosting = false;
    for (final car in race.cars) {
      if (car.finishedAt != null || car.retired) continue;
      speed = math.max(speed, car.speed.abs());
      final steer = car.steering.abs();
      if (car.speed.abs() > 70 && steer > .2) {
        slip = math.max(slip, ((steer - .2) / .7).clamp(0.0, 1.0));
      }
      final previous = _speed[car.driver.id] ?? car.speed;
      _speed[car.driver.id] = car.speed;
      if (!hold && dt > 0) {
        final rate = (car.speed - previous) / dt;
        if (rate > 40 && car.speed > 8 && car.speed < 420) {
          launch = math.max(launch, ((rate - 40) / 180).clamp(0.0, 1.0));
        }
      }
      if (car.boosting) boosting = true;
    }
    _hitAt += dt;
    if (race.bumps > 0 && _hitAt > .18) {
      _hitAt = 0;
      _once('audio/hit.m4a', .75);
    }
    final rising = launch > _launch;
    _launch = math.max(launch, math.max(0, _launch - dt / .6));
    final pace = (speed / 520).clamp(0.0, 1.0);
    _wantedEngine = hold ? .4 : .58 + pace * .16;
    if (_launch > 0) _wantedEngine = math.max(_wantedEngine, .78);
    _wantedSkid = slip * .62;
    _wantedRocket = boosting ? .7 : 0;
    _mixAt += dt;
    if (rising) _mixAt = .25;
    if (_mixAt < .25 && _engineLevel >= 0) return;
    _mixAt = 0;
    _kick();
  }

  var _wantedEngine = 0.0;
  var _wantedSkid = 0.0;
  var _wantedRocket = 0.0;

  Future<void> dispose() {
    _closed = true;
    _live = false;
    return _queue
        .then((_) async {
          for (final player in [
            _musicPlayer,
            _raceMusic,
            _engine,
            _skid,
            _rocket,
            ..._shots,
          ]) {
            await player?.dispose();
          }
        })
        .then((_) {}, onError: (Object _, StackTrace _) {});
  }

  void _loop(String asset, double level) {
    _musicLevel = level;
    if (_track == asset) {
      _run(
        () => _activeMusic()?.setVolume(music ? level : 0) ?? Future.value(),
      );
      return;
    }
    _track = asset;
    _run(() async {
      if (asset == 'audio/race.m4a') {
        await _warmRaceMusic();
        if (_track != asset || _closed) return;
        await _musicPlayer?.pause();
        final player = _raceMusic;
        if (player == null) return;
        await player.setVolume(music ? level : 0);
        await player.resume();
        return;
      }
      await _raceMusic?.pause();
      final player = _musicPlayer ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.stop();
      await player.setVolume(music ? level : 0);
      if (_track != asset || _closed) return;
      await player.play(AssetSource(asset));
    });
  }

  AudioPlayer? _activeMusic() =>
      _track == 'audio/race.m4a' ? _raceMusic : _musicPlayer;

  Future<void>? _raceMusicWarm;

  Future<void> _warmRaceMusic() {
    return _raceMusicWarm ??= _loadRaceMusic();
  }

  Future<void> _loadRaceMusic() async {
    try {
      await _shareSpeakers();
      final player = _raceMusic ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(0);
      if (_closed) return;
      await player.play(AssetSource('audio/race.m4a'));
      await player.pause();
    } catch (_) {
      _raceMusicWarm = null;
    }
  }

  void _once(String asset, double volume) =>
      _run(() => _playShot(asset, volume));

  Future<void> _playShot(String asset, double volume) async {
    final player = await _shotPlayer();
    if (player == null || _closed) return;
    await player.stop();
    await player.setVolume(volume);
    await player.play(AssetSource(asset), volume: volume);
  }

  Future<AudioPlayer?> _shotPlayer() async {
    if (_shots.isEmpty) {
      for (var i = 0; i < 4; i++) {
        _shots.add(AudioPlayer());
      }
    }
    final player = _shots[_shot];
    _shot = (_shot + 1) % _shots.length;
    return player;
  }

  void _kick() {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    _run(() async {
      try {
        await _mix();
      } finally {
        _busy = false;
        if (_again && !_closed) {
          _again = false;
          _kick();
        }
      }
    });
  }

  Future<void> _shareSpeakers() async {
    if (_speakers) return;
    _speakers = true;
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
            usageType: AndroidUsageType.game,
          ),
          iOS: AudioContextIOS(options: {AVAudioSessionOptions.mixWithOthers}),
        ),
      );
    } catch (_) {
      _speakers = false;
    }
  }

  var _speakers = false;

  Future<void> _mix() async {
    await _shareSpeakers();
    await _warmCars();
    final engine = _engine;
    final skid = _skid;
    final rocket = _rocket;
    if (engine == null || skid == null || rocket == null) return;
    await _audible(
      engine,
      'audio/engine.wav',
      _wantedEngine,
      _engineLevel,
      (level) => _engineLevel = level,
    );
    await _audible(
      skid,
      'audio/skid.wav',
      _wantedSkid,
      _skidLevel,
      (level) => _skidLevel = level,
    );
    await _audible(
      rocket,
      'audio/rocket.wav',
      _wantedRocket,
      _rocketLevel,
      (level) => _rocketLevel = level,
    );
  }

  Future<void> _startEngine() async {
    await _warmCars();
    final engine = _engine;
    if (engine == null || _closed) return;
    _wantedEngine = math.max(_wantedEngine, .58);
    await _audible(
      engine,
      'audio/engine.wav',
      _wantedEngine,
      -1,
      (level) => _engineLevel = level,
    );
  }

  Future<void> _audible(
    AudioPlayer player,
    String asset,
    double wanted,
    double current,
    void Function(double level) store,
  ) async {
    if (wanted <= .01) {
      if (current < 0) return;
      await player.setVolume(0);
      await player.pause();
      store(-1);
      return;
    }
    if (current < 0) {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource(asset), volume: wanted);
      store(wanted);
      return;
    }
    if ((current - wanted).abs() <= .04) return;
    await player.setVolume(wanted);
    store(wanted);
  }

  Future<void>? _carsWarm;

  Future<void> _warmCars() {
    return _carsWarm ??= _loadCars();
  }

  Future<void> _loadCars() async {
    try {
      final engine = _engine ??= AudioPlayer();
      final skid = _skid ??= AudioPlayer();
      final rocket = _rocket ??= AudioPlayer();
      if (_engineLevel >= 0) return;
      await engine.setReleaseMode(ReleaseMode.loop);
      await skid.setReleaseMode(ReleaseMode.loop);
      await rocket.setReleaseMode(ReleaseMode.loop);
    } catch (_) {
      _carsWarm = null;
      _engineLevel = -1;
    }
  }

  Future<void> _queue = Future<void>.value();

  void _run(Future<void> Function() action) {
    if (_closed) return;
    _queue = _queue
        .then((_) => action())
        .then((_) {}, onError: (Object _, StackTrace _) {});
  }
}
