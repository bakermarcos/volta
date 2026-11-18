import 'dart:math' as math;

import 'circuit.dart';
export 'circuit.dart';

const maxPlayers = 6;
const checkpointCount = 16;
typedef Checkpoint = ({double x, double y, double forwardX, double forwardY});
const playerColors = [
  0xFFBDFE55,
  0xFF60CBFF,
  0xFFFF8FAD,
  0xFFFFC65C,
  0xFFC5A0FF,
  0xFF56E2CC,
  0xFFFF7755,
  0xFFE9EEFA,
];

class Driver {
  const Driver(
    this.id,
    this.name,
    this.slot, {
    this.connected = true,
    this.ready = false,
    this.colorIndex,
    this.model = 0,
  });
  final String id, name;
  final int slot;
  final bool connected, ready;
  final int? colorIndex;
  final int model;
  int get paletteIndex => (colorIndex ?? slot) % playerColors.length;
  int get color => playerColors[paletteIndex];

  Driver copyWith({
    String? name,
    bool? connected,
    bool? ready,
    int? colorIndex,
    int? model,
  }) => Driver(
    id,
    name ?? this.name,
    slot,
    connected: connected ?? this.connected,
    ready: ready ?? this.ready,
    colorIndex: colorIndex ?? this.colorIndex,
    model: model ?? this.model,
  );
}

class ControlInput {
  const ControlInput({
    this.accelerate = false,
    this.reverse = false,
    this.boost = false,
    this.steer = 0,
    this.useItem = false,
  });
  final bool accelerate, reverse, boost, useItem;
  final double steer;
}

enum RaceItem {
  banana('Banana', '🍌'),
  oil('Óleo', '🛢️'),
  rocket('Foguete', '🚀'),
  leader('Frear líder', '👑'),
  comeback('Velocidade +50%', '⚡'),
  swap('Trocar posição', '🔀'),
  refill('Recarregar turbo', '🔋');

  const RaceItem(this.label, this.icon);
  final String label, icon;
}

class TrackHazard {
  TrackHazard(this.item, this.owner, this.x, this.y, this.expires);
  final RaceItem item;
  final Car owner;
  double x, y;
  final double expires;
  Car? target;
}

class PowerPickup {
  PowerPickup(this.x, this.y);
  final double x, y;
  double availableAt = 0;
}

class Car {
  Car(this.driver, int grid, [Circuit? track]) {
    final circuit = track ?? Circuit.island;
    final angle = -(grid ~/ 2) * 54 / circuit.length * math.pi * 2;
    final lane = (grid.isEven ? -1 : 1) * circuit.width * .22;
    final start = circuit.point(angle);
    heading = circuit.heading(angle);
    x = start.x - math.sin(heading) * lane;
    y = start.y + math.cos(heading) * lane;
    progress = angle;
    trackAngle = angle;
  }
  final Driver driver;
  late double x, y, heading, progress, trackAngle;
  double speed = 0, boostCharge = 1, boostCooldown = 0, steering = 0;
  double slowedUntil = 0, surgeUntil = 0, spinUntil = 0, powerNoticeUntil = 0;
  RaceItem? item;
  String? powerNotice;
  double? finishedAt;
  final lapTimes = <double>[];
  int nextCheckpoint = 1;
  double _lapStartedAt = 0;
  double raceTime(double elapsed) => finishedAt ?? elapsed;
  double lapTime(double elapsed) => finishedAt != null
      ? lapTimes.lastOrNull ?? 0
      : math.max(0, elapsed - _lapStartedAt);
  double? get bestLap => lapTimes.isEmpty ? null : lapTimes.reduce(math.min);
  bool retired = false, boosting = false, _boostReady = true;
  int get laps => lapTimes.length;
}

class Race {
  Race(
    List<Driver> drivers, {
    Circuit? circuit,
    this.totalLaps = 2,
    this.turbo = false,
    this.mirrored = false,
    this.reversed = false,
    this.timeTrial = false,
    math.Random? random,
  }) : _random = random ?? math.Random(),
       circuit = circuit ?? Circuit.island,
       cars = [
         for (var i = 0; i < drivers.length; i++) Car(drivers[i], i, circuit),
       ] {
    checkpoints = [
      for (var i = 0; i < checkpointCount; i++) _checkpoint(this.circuit, i),
    ];
    if (cars.length > 1 && !timeTrial) {
      final rows = (this.circuit.length / 14000).round().clamp(2, 4);
      for (var row = 1; row <= rows; row++) {
        final angle = row * 2 * math.pi / (rows + 1);
        final point = this.circuit.point(angle);
        final heading = this.circuit.heading(angle);
        for (final lane in [-.28, 0.0, .28]) {
          final offset = lane * this.circuit.width;
          pickups.add(
            PowerPickup(
              point.x - math.sin(heading) * offset,
              point.y + math.cos(heading) * offset,
            ),
          );
        }
      }
    }
    if (cars.length == 1) {
      final start = this.circuit.point(0);
      cars.first
        ..x = start.x
        ..y = start.y;
    }
  }
  final Circuit circuit;
  final int totalLaps;
  final bool turbo, mirrored, reversed, timeTrial;
  late final List<Checkpoint> checkpoints;
  static Checkpoint _checkpoint(Circuit track, int index) {
    final angle = index * math.pi * 2 / checkpointCount,
        point = track.point(angle),
        heading = track.heading(angle);
    return (
      x: point.x,
      y: point.y,
      forwardX: math.cos(heading),
      forwardY: math.sin(heading),
    );
  }

  final List<Car> cars;
  final math.Random _random;
  final pickups = <PowerPickup>[];
  final hazards = <TrackHazard>[];
  double? finishDeadline;
  double? get finishingIn =>
      finishDeadline == null ? null : math.max(0, finishDeadline! - elapsed);
  bool get lastLapStarted => cars.any(
    (car) =>
        !car.retired &&
        car.finishedAt == null &&
        car.laps > 0 &&
        car.laps >= totalLaps - 1,
  );
  double elapsed = 0;
  int bumps = 0;
  bool get finished => cars.every((c) => c.finishedAt != null || c.retired);
  List<Car> get standings => [...cars]
    ..sort((a, b) {
      if (a.retired != b.retired) return a.retired ? 1 : -1;
      if (a.finishedAt != null && b.finishedAt != null) {
        return a.finishedAt!.compareTo(b.finishedAt!);
      }
      return b.progress.compareTo(a.progress);
    });

  void step(
    double seconds,
    Map<String, ControlInput> inputs, {
    bool hold = false,
  }) {
    if (finished) return;
    bumps = 0;
    final dt = seconds.clamp(0.0, .05);
    if (!hold) {
      elapsed += dt;
      if (inputs.values.any((input) => input.useItem)) {
        final active = standings.where(_active).toList();
        for (final car in active) {
          if (inputs[car.driver.id]?.useItem == true) _useItem(car, active);
        }
      }
    }
    final previous = [for (final car in cars) (x: car.x, y: car.y)];
    final driven = [for (final car in cars) (x: car.x, y: car.y)];
    for (final (index, car) in cars.indexed) {
      if (car.finishedAt != null || car.retired) {
        car.boosting = false;
        continue;
      }
      if (elapsed < car.spinUntil) {
        car.boosting = false;
        continue;
      }
      final input = inputs[car.driver.id] ?? const ControlInput();
      final old = circuit.nearest(car.x, car.y, nearAngle: car.trackAngle);
      final pace =
          (turbo ? 1.4 : 1.0) *
          (elapsed < car.slowedUntil ? .55 : 1) *
          (elapsed < car.surgeUntil ? 1.5 : 1);
      final onRoad = old.distance < circuit.width / 2;
      if (!input.boost) car._boostReady = true;
      car.boosting =
          !hold &&
          input.boost &&
          car._boostReady &&
          input.accelerate &&
          !input.reverse &&
          onRoad &&
          car.speed > 40 &&
          car.boostCharge > 0;
      if (car.boosting) {
        car.boostCharge = (car.boostCharge - dt / 1.6).clamp(0.0, 1.0);
        car.boostCooldown = 1.2;
        if (car.boostCharge == 0) car._boostReady = false;
      } else {
        car.boostCooldown = math.max(0, car.boostCooldown - dt);
        if (car.boostCooldown == 0) {
          car.boostCharge = (car.boostCharge + dt * .16).clamp(0.0, 1.0);
        }
      }
      final previousSpeed = car.speed;
      final throttle = (input.accelerate ? 1 : 0) - (input.reverse ? 1 : 0);
      if (throttle == 0) {
        final drag = 170 * dt;
        car.speed = car.speed.abs() < drag
            ? 0
            : car.speed - car.speed.sign * drag;
      } else {
        final braking = car.speed != 0 && car.speed.sign != throttle.sign;
        car.speed +=
            throttle *
            (braking
                ? 300
                : car.boosting
                ? 555
                : 247.5) *
            dt *
            pace;
      }
      final maximum = (onRoad ? (car.boosting ? 615.0 : 405.0) : 195.0) * pace;
      if (car.speed > maximum) {
        car.speed = math.max(
          maximum,
          math.min(car.speed, previousSpeed - dt * (onRoad ? 180 : 110)),
        );
      }
      car.speed = math.max(onRoad ? -100.0 : -80.0, car.speed);
      if (hold) continue;
      car.steering +=
          (input.steer.clamp(-1.0, 1.0) - car.steering) * math.min(1, dt * 6);
      car.heading -=
          car.steering *
          (.6 + 1.1 * (car.speed.abs() / 200).clamp(0, 1)) *
          car.speed.sign *
          dt;
      car.x = (car.x + math.cos(car.heading) * car.speed * dt).clamp(
        circuit.minX - circuit.width * 2,
        circuit.maxX + circuit.width * 2,
      );
      car.y = (car.y + math.sin(car.heading) * car.speed * dt).clamp(
        circuit.minY - circuit.width * 2,
        circuit.maxY + circuit.width * 2,
      );
      driven[index] = (x: car.x, y: car.y);
    }
    if (hold) return;
    _resolveContacts();
    for (final car in cars) {
      if (car.finishedAt != null || car.retired) continue;
      var sample = circuit.nearest(car.x, car.y, nearAngle: car.trackAngle);
      if (sample.distance > circuit.driveableHalfWidth) {
        sample = circuit.nearest(car.x, car.y);
        car.trackAngle = sample.angle;
      }
      final limit = circuit.driveableHalfWidth - 24;
      if (sample.distance > limit) {
        final center = circuit.point(sample.angle);
        final ratio = limit / sample.distance;
        car.x = center.x + (car.x - center.x) * ratio;
        car.y = center.y + (car.y - center.y) * ratio;
      }
    }
    _resolveContacts();
    _settleShoulder();
    _updateHazards(dt);
    _collectPower();
    for (var i = 0; i < cars.length; i++) {
      final car = cars[i];
      if (car.finishedAt != null || car.retired) continue;
      final sample = circuit.nearest(car.x, car.y, nearAngle: car.trackAngle);
      car.trackAngle = sample.angle;
      final gate = checkpoints[car.nextCheckpoint];
      final drive = _cross(previous[i], driven[i], gate);
      final fraction = drive ?? _cross(driven[i], (x: car.x, y: car.y), gate);
      if (fraction != null) {
        if (car.nextCheckpoint == 0) {
          final crossedAt = drive == null
              ? elapsed
              : elapsed - dt + fraction * dt;
          car.lapTimes.add(crossedAt - car._lapStartedAt);
          car._lapStartedAt = crossedAt;
          if (car.laps == totalLaps) {
            car.finishedAt = crossedAt;
            car.speed = 0;
            car.boosting = false;
          }
        }
        car.nextCheckpoint = (car.nextCheckpoint + 1) % checkpointCount;
      }
      final segment =
          (car.nextCheckpoint + checkpointCount - 1) % checkpointCount;
      final offset = math.atan2(
        math.sin(sample.angle - segment * math.pi * 2 / checkpointCount),
        math.cos(sample.angle - segment * math.pi * 2 / checkpointCount),
      );
      car.progress =
          (car.laps * checkpointCount + segment) *
              math.pi *
              2 /
              checkpointCount +
          offset.clamp(-.1, math.pi * 2 / checkpointCount);
    }
    final remaining = cars
        .where((c) => !c.retired && c.finishedAt == null)
        .length;
    if (cars.length > 1 &&
        remaining == 1 &&
        cars.any((c) => c.finishedAt != null)) {
      finishDeadline ??= elapsed + 15;
    }
    if (finishDeadline != null && elapsed >= finishDeadline!) {
      for (final car in cars.where((c) => c.finishedAt == null)) {
        car.retired = true;
        car.speed = 0;
        car.boosting = false;
      }
    }
  }

  double? _cross(
    ({double x, double y}) from,
    ({double x, double y}) to,
    Checkpoint gate,
  ) {
    final before =
        (from.x - gate.x) * gate.forwardX + (from.y - gate.y) * gate.forwardY;
    final after =
        (to.x - gate.x) * gate.forwardX + (to.y - gate.y) * gate.forwardY;
    if (before > 0 || after <= 0) return null;
    final fraction = (-before / (after - before)).clamp(0.0, 1.0);
    final x = from.x + (to.x - from.x) * fraction - gate.x;
    final y = from.y + (to.y - from.y) * fraction - gate.y;
    if ((-x * gate.forwardY + y * gate.forwardX).abs() >
        circuit.driveableHalfWidth) {
      return null;
    }
    return fraction;
  }

  bool _active(Car car) => !car.retired && car.finishedAt == null;

  void _notice(Car car, String message) {
    car.powerNotice = message;
    car.powerNoticeUntil = elapsed + 2;
  }

  void _collectPower() {
    if (pickups.isEmpty) return;
    for (final car in cars.where(_active)) {
      for (final pickup in pickups) {
        if (elapsed < pickup.availableAt ||
            _distanceSquared(car.x, car.y, pickup.x, pickup.y) > 32 * 32) {
          continue;
        }
        pickup.availableAt = elapsed + 10;
        if (_random.nextInt(100) < 4 && car.item != RaceItem.swap) {
          car.item = RaceItem.swap;
        } else {
          final choices = RaceItem.values
              .where((item) => item != car.item && item != RaceItem.swap)
              .toList();
          car.item = choices[_random.nextInt(choices.length)];
        }
        break;
      }
    }
  }

  void _useItem(Car car, List<Car> active) {
    final item = car.item;
    if (item == null || elapsed < car.spinUntil) return;
    switch (item) {
      case RaceItem.banana:
      case RaceItem.oil:
        hazards.add(
          TrackHazard(
            item,
            car,
            car.x - math.cos(car.heading) * 40,
            car.y - math.sin(car.heading) * 40,
            elapsed + 15,
          ),
        );
      case RaceItem.rocket:
        Car? target;
        var range = 500 * 500.0;
        for (final rival in active) {
          if (rival == car) continue;
          final dx = rival.x - car.x, dy = rival.y - car.y;
          final distance = dx * dx + dy * dy;
          if (distance >= range ||
              dx * math.cos(car.heading) + dy * math.sin(car.heading) <= 0) {
            continue;
          }
          target = rival;
          range = distance;
        }
        if (target == null) {
          _notice(car, 'Sem alvo à frente');
          return;
        }
        hazards.add(
          TrackHazard(item, car, car.x, car.y, elapsed + 1.25)..target = target,
        );
      case RaceItem.leader:
        if (active.length < 2 || active.first == car) {
          _notice(car, 'Aguarde outro líder');
          return;
        }
        _slow(active.first, 3, 'Líder desacelerado');
      case RaceItem.comeback:
        if (active.length < 2 || active.last != car) {
          _notice(car, 'Só para o último lugar');
          return;
        }
        car.surgeUntil = elapsed + 4;
      case RaceItem.swap:
        final rivals = active
            .where((r) => r != car && r.laps == car.laps)
            .toList();
        if (rivals.isEmpty) {
          _notice(car, 'Sem rival na mesma volta');
          return;
        }
        final rival = rivals[_random.nextInt(rivals.length)];
        final (x, y, heading, angle, progress, checkpoint) = (
          car.x,
          car.y,
          car.heading,
          car.trackAngle,
          car.progress,
          car.nextCheckpoint,
        );
        car
          ..x = rival.x
          ..y = rival.y
          ..heading = rival.heading
          ..trackAngle = rival.trackAngle
          ..progress = rival.progress
          ..nextCheckpoint = rival.nextCheckpoint;
        rival
          ..x = x
          ..y = y
          ..heading = heading
          ..trackAngle = angle
          ..progress = progress
          ..nextCheckpoint = checkpoint;
        _notice(rival, 'Posição trocada');
      case RaceItem.refill:
        car.boostCharge = 1;
        car.boostCooldown = 0;
    }
    car.item = null;
    _notice(car, item.label);
  }

  void _slow(Car car, double duration, String message) {
    car.speed *= .55;
    car.slowedUntil = math.max(car.slowedUntil, elapsed + duration);
    _notice(car, message);
  }

  void _spin(Car car, double duration, String message) {
    car.speed = 0;
    car.spinUntil = elapsed + duration;
    _notice(car, message);
  }

  void _updateHazards(double dt) {
    hazards.removeWhere((hazard) {
      if (elapsed >= hazard.expires) return true;
      final target = hazard.target;
      if (target != null) {
        if (!_active(target)) return true;
        final distance = math.sqrt(
          _distanceSquared(hazard.x, hazard.y, target.x, target.y),
        );
        if (distance <= 22 + dt * 1000) {
          _spin(target, .9, 'Atingido por foguete');
          return true;
        }
        final step = dt * 1000 / distance;
        hazard.x += (target.x - hazard.x) * step;
        hazard.y += (target.y - hazard.y) * step;
        return false;
      }
      for (final rival in cars) {
        if (rival == hazard.owner ||
            !_active(rival) ||
            _distanceSquared(rival.x, rival.y, hazard.x, hazard.y) > 28 * 28) {
          continue;
        }
        if (hazard.item == RaceItem.banana) {
          _spin(rival, .6, 'Escorregou na banana');
        } else {
          _slow(rival, 1.6, 'Passou pelo óleo');
        }
        return true;
      }
      return false;
    });
  }

  static double _distanceSquared(double x, double y, double a, double b) {
    final dx = x - a, dy = y - b;
    return dx * dx + dy * dy;
  }

  void _resolveContacts() {
    for (var pass = 0; pass < 64; pass++) {
      var touching = false;
      for (var i = 0; i < cars.length; i++) {
        for (var j = i + 1; j < cars.length; j++) {
          final a = cars[i], b = cars[j];
          var dx = b.x - a.x, dy = b.y - a.y;
          var squared = dx * dx + dy * dy;
          if (squared >= 48 * 48 - .001) continue;
          if (squared < .000001) {
            dx = 1;
            dy = 0;
            squared = 1;
          }
          touching = true;
          final distance = math.sqrt(squared),
              nx = dx / distance,
              ny = dy / distance;
          final aStopped = a.retired || a.finishedAt != null;
          final bStopped = b.retired || b.finishedAt != null;
          final aShare = aStopped && !bStopped
              ? 0.0
              : bStopped && !aStopped
              ? 1.0
              : .5;
          final push = 48 - distance;
          a.x -= nx * push * aShare;
          a.y -= ny * push * aShare;
          b.x += nx * push * (1 - aShare);
          b.y += ny * push * (1 - aShare);
          final closing =
              (math.cos(a.heading) * a.speed - math.cos(b.heading) * b.speed) *
                  nx +
              (math.sin(a.heading) * a.speed - math.sin(b.heading) * b.speed) *
                  ny;
          if (pass == 0 && closing > 90) bumps++;
          if (pass == 0 && closing > 20) {
            if (!aStopped) a.speed *= .98;
            if (!bStopped) b.speed *= .98;
          }
        }
      }
      if (!touching) break;
    }
  }

  void _settleShoulder() {
    const body = 48.0;
    final limit = circuit.driveableHalfWidth - 24;
    for (var pass = 0; pass < 8; pass++) {
      var adjusted = false;
      for (final car in cars) {
        if (car.finishedAt != null || car.retired) continue;
        var sample = circuit.nearest(car.x, car.y, nearAngle: car.trackAngle);
        if (sample.distance > circuit.driveableHalfWidth) {
          sample = circuit.nearest(car.x, car.y);
          car.trackAngle = sample.angle;
        }
        if (sample.distance <= limit) continue;
        final center = circuit.point(sample.angle);
        final ratio = limit / sample.distance;
        car.x = center.x + (car.x - center.x) * ratio;
        car.y = center.y + (car.y - center.y) * ratio;
        adjusted = true;
        var rx = car.x - center.x, ry = car.y - center.y;
        final radial = math.sqrt(rx * rx + ry * ry);
        if (radial < .001) continue;
        rx /= radial;
        ry /= radial;
        final tx = -ry, ty = rx;
        for (final other in cars) {
          if (identical(other, car)) continue;
          var dx = car.x - other.x, dy = car.y - other.y;
          var distance = math.sqrt(dx * dx + dy * dy);
          if (distance >= body - .001) continue;
          if (distance < .001) {
            dx = tx;
            dy = ty;
            distance = 1;
          }
          final need = body - distance;
          final side = dx * tx + dy * ty;
          final sign = side >= 0 ? 1.0 : -1.0;
          car.x += tx * sign * need;
          car.y += ty * sign * need;
        }
      }
      if (!adjusted) break;
    }
  }
}

String formatRaceTime(double seconds) {
  final hundredths = (math.max(0, seconds) * 100).floor();
  return '${hundredths ~/ 6000}:${((hundredths ~/ 100) % 60).toString().padLeft(2, '0')}.${(hundredths % 100).toString().padLeft(2, '0')}';
}
