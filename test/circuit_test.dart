import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:volta/game/race.dart';
import 'package:volta/ui/race_scene.dart';

void main() {
  test('all 16 reference circuits are closed, finite and have usable starting grids', () {
    expect(Circuit.catalog.length, 17);
    expect(Circuit.catalog.map((c) => c.name).toSet().length, 17);
    for (final track in Circuit.catalog) {
      expect(track.points.length, 513);
      expect(track.width, greaterThanOrEqualTo(4 * 30.6 + 40));
      expect(track.overlapsRoad(margin: 20), false, reason: track.name);
      expect(track.height(0), 1);
      expect(track.surfaceHeight(0, 0), 1);
      expect(track.length, greaterThan(1000), reason: track.name);
      for (final angle in [0.0, .001, 1.2, 3.5, math.pi * 2 - .001]) {
        final p = track.point(angle);
        final sample = track.nearest(p.x, p.y);
        expect(sample.distance, lessThan(.01), reason: track.name);
        expect(track.heading(angle).isFinite, true, reason: track.name);
      }
      expect(track.point(0), track.point(math.pi * 2));
      final race = Race([
        for (var i = 0; i < maxPlayers; i++) Driver('$i', 'P$i', i),
      ], circuit: track);
      for (final car in race.cars) {
        expect(
          track.nearest(car.x, car.y).distance,
          lessThan(track.width / 2),
          reason: '${track.name}: grid ${car.driver.slot}',
        );
      }
    }
  });
  test('mirroring and reversing preserve width, length and lap direction', () {
    final original = Circuit.catalog.firstWhere((c) => c.name == 'Brasil');
    for (final mirrored in [false, true]) {
      for (final reversed in [false, true]) {
        final variant = original.variant(
          mirrored: mirrored,
          reversed: reversed,
        );
        expect(variant.length, original.length);
        expect(variant.width, original.width);
        final p = original.point(reversed ? -.7 : .7),
            transformed = variant.point(.7);
        expect(
          transformed.x,
          closeTo(mirrored ? original.minX + original.maxX - p.x : p.x, .001),
        );
        expect(transformed.y, closeTo(p.y, .001));
        expect(variant.overlapsRoad(margin: 20), false);
      }
    }
  });
  test(
    'split screen gives 1–6 players independent non-overlapping full coverage',
    () {
      for (var count = 1; count <= maxPlayers; count++) {
        final views = playerViewports(count);
        expect(views.length, count);
        expect(
          views.fold(0.0, (sum, r) => sum + r.width * r.height),
          closeTo(1, .000001),
        );
        for (var i = 0; i < count; i++) {
          expect(views[i].left, greaterThanOrEqualTo(0));
          expect(views[i].right, lessThanOrEqualTo(1));
          expect(views[i].top, greaterThanOrEqualTo(0));
          expect(views[i].bottom, lessThanOrEqualTo(1));
          for (var j = i + 1; j < count; j++) {
            expect(views[i].overlaps(views[j]), false);
          }
        }
      }
    },
  );
}
