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
];

class Driver {
  const Driver(
    this.id,
    this.name,
    this.slot, {
    this.connected = true,
    this.ready = false,
  });
  final String id, name;
  final int slot;
  final bool connected, ready;
  int get color => playerColors[slot % playerColors.length];
}

class ControlInput {
  const ControlInput({
    this.accelerate = false,
    this.reverse = false,
    this.boost = false,
    this.steer = 0,
  });
  final bool accelerate, reverse, boost;
  final double steer;
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
  }) : circuit = circuit ?? Circuit.island,
       cars = [
         for (var i = 0; i < drivers.length; i++) Car(drivers[i], i, circuit),
       ] {
    checkpoints = [
      for (var i = 0; i < checkpointCount; i++) _checkpoint(this.circuit, i),
    ];
    if (cars.length == 1) {
      final start = this.circuit.point(0);
      cars.first
        ..x = start.x
        ..y = start.y;
    }
  }
  final Circuit circuit;
  final int totalLaps;
  final bool turbo, mirrored, reversed;
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
  double? finishDeadline;
  double? get finishingIn =>
      finishDeadline == null ? null : math.max(0, finishDeadline! - elapsed);
  double elapsed = 0;
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
    final dt = seconds.clamp(0.0, .05);
    if (!hold) elapsed += dt;
    final previous = [for (final car in cars) (x: car.x, y: car.y)];
    for (final car in cars) {
      if (car.finishedAt != null || car.retired) {
        car.boosting = false;
        continue;
      }
      final input = inputs[car.driver.id] ?? const ControlInput();
      final old = circuit.nearest(car.x, car.y, nearAngle: car.trackAngle);
      final pace = turbo ? 1.4 : 1.0;
      final onRoad = old.distance < circuit.width / 2;
      if (!input.boost) car._boostReady = true;
      car.boosting =
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
                ? 370
                : 165) *
            dt *
            pace;
      }
      final maximum = (onRoad ? (car.boosting ? 410.0 : 270.0) : 195.0) * pace;
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
    }
    if (hold) return;
    _resolveContacts();
    for (var i = 0; i < cars.length; i++) {
      final car = cars[i];
      if (car.finishedAt != null || car.retired) continue;
      final sample = circuit.nearest(car.x, car.y, nearAngle: car.trackAngle);
      car.trackAngle = sample.angle;
      final limit = circuit.driveableHalfWidth - 24;
      if (sample.distance > limit) {
        final center = circuit.point(sample.angle);
        final ratio = limit / sample.distance;
        car.x = center.x + (car.x - center.x) * ratio;
        car.y = center.y + (car.y - center.y) * ratio;
      }
      final gate = checkpoints[car.nextCheckpoint];
      final before =
          (previous[i].x - gate.x) * gate.forwardX +
          (previous[i].y - gate.y) * gate.forwardY;
      final after =
          (car.x - gate.x) * gate.forwardX + (car.y - gate.y) * gate.forwardY;
      if (before <= 0 && after > 0) {
        final fraction = (-before / (after - before)).clamp(0.0, 1.0);
        final x = previous[i].x + (car.x - previous[i].x) * fraction - gate.x;
        final y = previous[i].y + (car.y - previous[i].y) * fraction - gate.y;
        if ((-x * gate.forwardY + y * gate.forwardX).abs() <=
            circuit.driveableHalfWidth) {
          if (car.nextCheckpoint == 0) {
            final crossedAt = elapsed - dt + fraction * dt;
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

  void _resolveContacts() {
    for (var pass = 0; pass < 32; pass++) {
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
          if (pass == 0 && closing > 20) {
            if (!aStopped) a.speed *= .98;
            if (!bStopped) b.speed *= .98;
          }
        }
      }
      if (!touching) break;
    }
  }
}

String formatRaceTime(double seconds) {
  final hundredths = (math.max(0, seconds) * 100).floor();
  return '${hundredths ~/ 6000}:${((hundredths ~/ 100) % 60).toString().padLeft(2, '0')}.${(hundredths % 100).toString().padLeft(2, '0')}';
}
