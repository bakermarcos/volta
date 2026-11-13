import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:volta/game/race.dart';

void main() {
  const drivers = [Driver('a', 'A', 0), Driver('b', 'B', 1)];
  void holdOnRoad(Race race, ControlInput input, double seconds) {
    final car = race.cars.first;
    for (final other in race.cars.skip(1)) {
      other.retired = true;
    }
    for (var i = 0; i < (seconds / .02).round(); i++) {
      final p = Circuit.island.point(0);
      car.x = p.x;
      car.y = p.y;
      car.heading = Circuit.island.heading(0);
      race.step(.02, {'a': input});
    }
  }

  test('forward speed is bounded and releasing brakes to zero', () {
    final race = Race(drivers);
    holdOnRoad(race, const ControlInput(accelerate: true), 3);
    expect(race.cars.first.speed, 405);
    expect(race.cars.last.speed, 0);
    holdOnRoad(race, const ControlInput(), 3);
    expect(race.cars.first.speed, 0);
  });
  test(
    'reverse brakes first, then moves backwards with a lower speed limit',
    () {
      final race = Race(drivers);
      final car = race.cars.first;
      car.speed = 120;
      holdOnRoad(race, const ControlInput(reverse: true), .2);
      expect(car.speed, closeTo(60, .001));
      holdOnRoad(race, const ControlInput(reverse: true), 2);
      expect(car.speed, -100);
      expect(car.progress, lessThan(.1));
    },
  );
  test(
    'boost increases speed, empties, recharges and never boosts reverse',
    () {
      final race = Race(drivers);
      final car = race.cars.first;
      car.speed = 200;
      holdOnRoad(race, const ControlInput(accelerate: true, boost: true), .5);
      expect(car.boosting, isTrue);
      expect(car.speed, greaterThan(405));
      expect(car.boostCharge, lessThan(1));
      holdOnRoad(race, const ControlInput(accelerate: true, boost: true), 4);
      expect(car.boosting, isFalse);
      expect(car.speed, lessThanOrEqualTo(405));
      holdOnRoad(race, const ControlInput(), 8);
      expect(car.boostCharge, closeTo(1, .001));
      holdOnRoad(race, const ControlInput(reverse: true, boost: true), 2);
      expect(car.boosting, isFalse);
      expect(car.boostCharge, 1);
    },
  );
  test('last lap starts after a completed lap, not on a one-lap grid', () {
    final single = Race(drivers, totalLaps: 1);
    expect(single.lastLapStarted, isFalse);
    single.cars.first.lapTimes.add(12);
    single.cars.first.finishedAt = 12;
    expect(single.lastLapStarted, isFalse);
    final two = Race(drivers, totalLaps: 2);
    expect(two.lastLapStarted, isFalse);
    two.cars.first.lapTimes.add(20);
    expect(two.lastLapStarted, isTrue);
  });
  test('countdown hold revs in place and refuses boost', () {
    final race = Race(drivers);
    final car = race.cars.first;
    final x = car.x, y = car.y;
    for (var i = 0; i < 60; i++) {
      race.step(.05, {
        car.driver.id: const ControlInput(accelerate: true, boost: true),
      }, hold: true);
    }
    expect(car.x, x);
    expect(car.y, y);
    expect(car.speed, greaterThan(40));
    expect(car.boosting, isFalse);
    expect(car.boostCharge, 1);
  });
  void crossGate(Race race, Car car, {int? gateIndex, bool backwards = false}) {
    final gate = race.checkpoints[gateIndex ?? car.nextCheckpoint];
    final direction = backwards ? -1 : 1;
    car.trackAngle =
        (gateIndex ?? car.nextCheckpoint) * math.pi * 2 / checkpointCount;
    car.x = gate.x - gate.forwardX * direction;
    car.y = gate.y - gate.forwardY * direction;
    car.heading =
        math.atan2(gate.forwardY, gate.forwardX) + (backwards ? math.pi : 0);
    car.speed = 200;
    race.step(.02, {car.driver.id: const ControlInput(accelerate: true)});
  }

  test('ordered checkpoints reject shortcuts and wrong-way crossings', () {
    final race = Race([drivers.first], totalLaps: 1);
    final car = race.cars.first;
    crossGate(race, car, gateIndex: 0);
    expect(car.laps, 0);
    expect(car.nextCheckpoint, 1);
    crossGate(race, car, backwards: true);
    expect(car.nextCheckpoint, 1);
    for (var i = 0; i < checkpointCount; i++) {
      crossGate(race, car);
    }
    expect(car.laps, 1);
    expect(race.finished, isTrue);
  });

  test(
    'grass shoulder counts checkpoints and invisible boundary blocks deep cuts',
    () {
      final race = Race([drivers.first], totalLaps: 1);
      final car = race.cars.first;
      for (var i = 0; i < checkpointCount; i++) {
        final index = car.nextCheckpoint, gate = race.checkpoints[index];
        car.trackAngle = index * math.pi * 2 / checkpointCount;
        car.x =
            gate.x -
            gate.forwardX -
            gate.forwardY * (race.circuit.width / 2 + 35);
        car.y =
            gate.y -
            gate.forwardY +
            gate.forwardX * (race.circuit.width / 2 + 35);
        car.heading = math.atan2(gate.forwardY, gate.forwardX);
        car.speed = 200;
        race.step(.02, {car.driver.id: const ControlInput(accelerate: true)});
      }
      expect(race.finished, isTrue);
      final bounded = Race([drivers.first]);
      final c = bounded.cars.first;
      c.x = 0;
      c.y = 0;
      bounded.step(.02, {});
      expect(
        bounded.circuit.nearest(c.x, c.y, nearAngle: c.trackAngle).distance,
        lessThanOrEqualTo(bounded.circuit.driveableHalfWidth - 23.9),
      );
      expect(c.laps, 0);
    },
  );

  test('turbo setting increases cruise and boost speeds', () {
    final race = Race([drivers.first], turbo: true);
    holdOnRoad(race, const ControlInput(accelerate: true), 5);
    expect(race.cars.first.speed, closeTo(567, .01));
    holdOnRoad(race, const ControlInput(accelerate: true, boost: true), 1);
    expect(race.cars.first.speed, greaterThan(615));
  });

  test('15 second deadline starts only with one remaining racer', () {
    final race = Race([...drivers, const Driver('c', 'C', 2)], totalLaps: 1);
    for (var i = 0; i < checkpointCount; i++) {
      crossGate(race, race.cars.first);
    }
    expect(race.finishDeadline, isNull);
    for (var i = 0; i < checkpointCount; i++) {
      crossGate(race, race.cars[1]);
    }
    expect(race.finishingIn, closeTo(15, .001));
    expect(race.finished, isFalse);
    for (var i = 0; i < 301; i++) {
      race.step(.05, {});
    }
    expect(race.finished, isTrue);
    expect(race.cars.last.retired, isTrue);
    expect(race.standings.last.driver.id, 'c');
  });

  test('off-road driving earns no progress; long frames are bounded', () {
    final race = Race(drivers);
    final car = race.cars.first;
    car.x = 0;
    car.y = 0;
    car.speed = 270;
    race.step(10, {'a': const ControlInput(accelerate: true)});
    expect(car.nextCheckpoint, 1);
    expect(car.laps, 0);
    expect(car.speed, closeTo(264.5, .001));
    expect(race.elapsed, .05);
  });
  test('steering is analog, smoothed and constrained', () {
    final race = Race(drivers);
    final car = race.cars.first;
    car.speed = 100;
    race.step(.02, {'a': const ControlInput(accelerate: true, steer: .5)});
    expect(car.steering, inExclusiveRange(0, .5));
    holdOnRoad(race, const ControlInput(accelerate: true, steer: 99), 1);
    expect(car.steering, lessThanOrEqualTo(1));
  });
  test('right turns toward camera right, left toward camera left, and reverse inverts yaw', () {
    for (final steer in [-1.0, 1.0]) {
      final race = Race(drivers);
      final car = race.cars.first;
      car.heading = 0;
      car.speed = 180;
      final y = car.y;
      race.step(.05, {'a': ControlInput(accelerate: true, steer: steer)});
      expect((car.y - y).sign, -steer);
      expect(car.heading.abs(), lessThan(.04));
      car.heading = 0;
      car.speed = -80;
      race.step(.05, {'a': ControlInput(reverse: true, steer: steer)});
      expect(car.heading.sign, steer);
    }
  });
  test(
    'grass slows progressively to 195 while preserving useful acceleration',
    () {
      final race = Race(drivers);
      race.cars.last.retired = true;
      final car = race.cars.first;
      car.speed = 270;
      for (var i = 0; i < 100; i++) {
        car.x = 0;
        car.y = 0;
        race.step(.02, {'a': const ControlInput(accelerate: true)});
        expect(car.speed, greaterThanOrEqualTo(195));
      }
      expect(car.speed, 195);
    },
  );
  test(
    'kart contact separates visible bodies without braking a same-speed pack',
    () {
      final race = Race(drivers);
      final a = race.cars.first, b = race.cars.last;
      final p = race.circuit.point(0);
      a.x = p.x;
      a.y = p.y;
      a.heading = 0;
      a.speed = 100;
      b.x = p.x + 20;
      b.y = p.y;
      b.heading = 0;
      b.speed = 100;
      race.step(0, {});
      expect(
        math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)),
        closeTo(48, .001),
      );
      expect(a.speed, 100);
      expect(b.speed, 100);
    },
  );
  test('configured laps finish solo and preserve lap and race clocks', () {
    for (final laps in [1, 2, 3, 5]) {
      final race = Race([drivers.first], totalLaps: laps);
      final car = race.cars.first;
      for (var lap = 0; lap < laps; lap++) {
        for (var gate = 0; gate < checkpointCount; gate++) {
          crossGate(race, car);
        }
        expect(car.laps, lap + 1);
        expect(race.finished, lap == laps - 1);
      }
      expect(
        car.lapTimes.reduce((a, b) => a + b),
        closeTo(car.finishedAt!, .000001),
      );
      expect(car.bestLap, isNotNull);
      expect(car.raceTime(999), car.finishedAt);
    }
    expect(formatRaceTime(65.129), '1:05.12');
  });
  test('six coincident karts separate and a finished kart remains a solid obstacle', () {
    final race = Race([for (var i = 0; i < 6; i++) Driver('$i', 'P$i', i)]);
    for (final c in race.cars) {
      c.x = 500;
      c.y = 0;
    }
    race.step(0, {});
    for (var i = 0; i < 6; i++) {
      for (var j = i + 1; j < 6; j++) {
        final a = race.cars[i], b = race.cars[j];
        expect(
          math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)),
          greaterThan(47.9),
        );
      }
    }
    final parked = Race(drivers);
    parked.cars.first
      ..x = 500
      ..y = 0
      ..finishedAt = 10;
    parked.cars.last
      ..x = 510
      ..y = 0;
    parked.step(0, {});
    expect(parked.cars.first.x, 500);
    expect(parked.cars.last.x, 548);
  });
  test('karts packed on the shoulder stay separated and stop jittering', () {
    final race = Race(drivers);
    final circuit = race.circuit;
    const angle = 0.0;
    final center = circuit.point(angle);
    final heading = circuit.heading(angle);
    final nx = -math.sin(heading), ny = math.cos(heading);
    final limit = circuit.driveableHalfWidth - 24;
    final a = race.cars.first, b = race.cars.last;
    a.trackAngle = angle;
    b.trackAngle = angle;
    a.speed = 0;
    b.speed = 0;
    a.x = center.x + nx * (limit + 30);
    a.y = center.y + ny * (limit + 30);
    b.x = a.x + math.cos(heading) * 10;
    b.y = a.y + math.sin(heading) * 10;
    race.step(0, {});
    race.step(0, {});
    double apart(Car left, Car right) => math.sqrt(
      math.pow(left.x - right.x, 2) + math.pow(left.y - right.y, 2),
    );
    expect(apart(a, b), greaterThan(47.9));
    expect(
      circuit.nearest(a.x, a.y, nearAngle: a.trackAngle).distance,
      lessThanOrEqualTo(limit + .2),
    );
    expect(
      circuit.nearest(b.x, b.y, nearAngle: b.trackAngle).distance,
      lessThanOrEqualTo(limit + .2),
    );
    final ax = a.x, ay = a.y, bx = b.x, by = b.y;
    race.step(0, {});
    expect(a.x, closeTo(ax, .05));
    expect(a.y, closeTo(ay, .05));
    expect(b.x, closeTo(bx, .05));
    expect(b.y, closeTo(by, .05));
  });
  test('circuit lookup is continuous at the lap seam', () {
    for (final angle in [-.001, .001, 1.2, 3.5, math.pi * 2 - .001]) {
      final p = Circuit.island.point(angle);
      final near = Circuit.island.nearest(p.x, p.y);
      final delta = math.atan2(
        math.sin(near.angle - angle),
        math.cos(near.angle - angle),
      );
      expect(delta.abs(), lessThan(.001));
      expect(near.distance, lessThan(.1));
    }
  });
}
