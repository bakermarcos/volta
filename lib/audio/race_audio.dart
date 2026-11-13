import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';

import '../game/race.dart';

class RaceAudio {
  bool _music = true;
  bool get music => _music;
  set music(bool value) {
    _music = value;
    final player = _musicPlayer;
    if (player == null) return;
    _run(() => player.setVolume(value ? _musicLevel : 0));
  }

  final _boosting = <String, bool>{};
  final _speed = <String, double>{};
  AudioPlayer? _musicPlayer;
  AudioPlayer? _engine;
  AudioPlayer? _skid;
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
  var _engineRate = 0.0;
  var _skidLevel = -1.0;

  void menu() {
    _live = false;
    _run(_quietCars);
    _loop('audio/menu.m4a', .4);
  }

  void race() {
    _live = true;
    _paused = false;
    _boosting.clear();
    _speed.clear();
    _run(() async {
      await _engine?.resume();
      await _skid?.resume();
    });
    _loop('audio/race.m4a', .46);
  }

  void climax() {
    _live = true;
    if (music) _once('audio/final_lap.m4a', .85);
    _loop('audio/climax.m4a', .5);
  }

  void win() {
    _live = false;
    _run(() async {
      await _quietCars();
      await _musicPlayer?.stop();
      _track = '';
      if (_music) await _playShot('audio/win.m4a', .85);
    });
  }

  Future<void> _quietCars() async {
    final engine = _engine;
    if (engine != null) {
      await engine.setVolume(0);
      await engine.pause();
      _engineLevel = 0;
    }
    final skid = _skid;
    if (skid != null) {
      await skid.setVolume(0);
      await skid.pause();
      _skidLevel = 0;
    }
  }

  void count(int value) =>
      _once(value == 0 ? 'audio/go.m4a' : 'audio/beep.m4a', .7);

  void pause() {
    _paused = true;
    _run(() async {
      await _musicPlayer?.pause();
      await _engine?.pause();
      await _skid?.pause();
    });
  }

  void resume() {
    _paused = false;
    _run(() async {
      if (_track.isNotEmpty) await _musicPlayer?.resume();
      if (_live) {
        await _engine?.resume();
        await _skid?.resume();
      }
    });
  }

  void drive(Race race, double dt, {required bool hold}) {
    if (!_live || _paused || _closed) return;
    var speed = 0.0;
    var slip = 0.0;
    var launch = 0.0;
    var boost = false;
    var boosting = false;
    for (final car in race.cars) {
      if (car.finishedAt != null || car.retired) {
        _boosting[car.driver.id] = false;
        continue;
      }
      speed = math.max(speed, car.speed.abs());
      final steer = car.steering.abs();
      if (car.speed.abs() > 70 && steer > .2) {
        slip = math.max(slip, ((steer - .2) / .7).clamp(0.0, 1.0));
      }
      final previous = _speed[car.driver.id] ?? car.speed;
      _speed[car.driver.id] = car.speed;
      if (!hold && dt > 0) {
        final rate = (car.speed - previous) / dt;
        if (rate > 70 && car.speed > 20 && car.speed < 360) {
          launch = math.max(launch, ((rate - 70) / 180).clamp(0.0, 1.0));
        }
      }
      final was = _boosting[car.driver.id] ?? false;
      if (car.boosting && !was) boost = true;
      if (car.boosting) boosting = true;
      _boosting[car.driver.id] = car.boosting;
    }
    if (boost) _once('audio/turbo.m4a', .65);
    _hitAt += dt;
    if (race.bumps > 0 && _hitAt > .18) {
      _hitAt = 0;
      _once('audio/hit.m4a', .75);
    }
    _wantedEngine = hold ? .16 : .34 + (boosting ? .08 : 0);
    _wantedRate = (.78 + (speed / 520).clamp(0.0, 1.0) * .7).clamp(.7, 1.6);
    _wantedSkid = math.max(slip * .62, launch * .4);
    _mixAt += dt;
    if (_mixAt < .08 && _engineLevel >= 0) return;
    _mixAt = 0;
    _kick();
  }

  var _wantedEngine = 0.0;
  var _wantedRate = 1.0;
  var _wantedSkid = 0.0;

  Future<void> dispose() {
    _closed = true;
    _live = false;
    return _queue
        .then((_) async {
          for (final player in [_musicPlayer, _engine, _skid, ..._shots]) {
            await player?.dispose();
          }
        })
        .then((_) {}, onError: (Object _, StackTrace _) {});
  }

  void _loop(String asset, double level) {
    _musicLevel = level;
    if (_track == asset) {
      _run(() => _musicPlayer?.setVolume(music ? level : 0) ?? Future.value());
      return;
    }
    _track = asset;
    _run(() async {
      final player = _musicPlayer ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.stop();
      await player.setVolume(music ? level : 0);
      if (_track != asset || _closed) return;
      await player.play(AssetSource(asset));
    });
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

  Future<void> _mix() async {
    final engine = _engine ??= AudioPlayer();
    final skid = _skid ??= AudioPlayer();
    if (_engineLevel < 0) {
      await engine.setReleaseMode(ReleaseMode.loop);
      await skid.setReleaseMode(ReleaseMode.loop);
      await engine.setVolume(0);
      await skid.setVolume(0);
      await engine.play(AssetSource('audio/engine.wav'));
      await skid.play(AssetSource('audio/skid.wav'));
      _engineLevel = 0;
      _skidLevel = 0;
    }
    if ((_engineLevel - _wantedEngine).abs() > .02) {
      await engine.setVolume(_wantedEngine);
      _engineLevel = _wantedEngine;
    }
    if ((_engineRate - _wantedRate).abs() > .04) {
      await engine.setPlaybackRate(_wantedRate);
      _engineRate = _wantedRate;
    }
    if ((_skidLevel - _wantedSkid).abs() > .03) {
      await skid.setVolume(_wantedSkid);
      _skidLevel = _wantedSkid;
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
