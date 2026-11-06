import 'dart:math' as math;

import 'track_layouts.dart';

typedef TrackPoint = ({double x, double y});

class Circuit {
  Circuit(this.name, List<(double, double)> outline, {this.width = 240}) {
    final raw = _rounded([
      for (final (x, y) in outline) (x: x, y: y),
    ], width * 1.15);
    final distances = <double>[0];
    for (var i = 0; i < raw.length; i++) {
      final a = raw[i], b = raw[(i + 1) % raw.length];
      distances.add(
        distances.last +
            math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2)),
      );
    }
    length = distances.last;
    var segment = 0;
    points = List.generate(513, (i) {
      final distance = i / 512 * length;
      while (segment < raw.length - 1 && distances[segment + 1] < distance) {
        segment++;
      }
      final a = raw[segment], b = raw[(segment + 1) % raw.length];
      final t =
          (distance - distances[segment]) /
          (distances[segment + 1] - distances[segment]);
      return (x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t);
    });
    for (var attempt = 0; attempt < 8 && overlapsRoad(margin: 20); attempt++) {
      for (var i = 0; i < points.length; i++) {
        points[i] = (x: points[i].x * 1.15, y: points[i].y * 1.15);
      }
      length *= 1.15;
    }
    _alignStart();
    minX = points.map((p) => p.x).reduce(math.min);
    maxX = points.map((p) => p.x).reduce(math.max);
    minY = points.map((p) => p.y).reduce(math.min);
    maxY = points.map((p) => p.y).reduce(math.max);
  }
  final String name;
  final double width;
  late double length;
  late final double minX, maxX, minY, maxY;
  late final List<TrackPoint> points;
  static final island = Circuit('Ilha Brisa', [
    for (var i = 0; i < 256; i++)
      (
        380 * math.cos(i * math.pi / 128) + 45 * math.sin(i * math.pi / 64),
        230 * math.sin(i * math.pi / 128) +
            25 * math.sin(i * math.pi * 3 / 128),
      ),
  ]);
  static final catalog = [
    island,
    for (final entry in referenceLayouts.entries)
      Circuit(entry.key, entry.value),
  ];

  static List<TrackPoint> _rounded(List<TrackPoint> input, double radius) {
    final result = <TrackPoint>[];
    for (var i = 0; i < input.length; i++) {
      final a = input[(i + input.length - 1) % input.length],
          b = input[i],
          c = input[(i + 1) % input.length];
      final inX = b.x - a.x,
          inY = b.y - a.y,
          outX = c.x - b.x,
          outY = c.y - b.y;
      final inLength = math.sqrt(inX * inX + inY * inY),
          outLength = math.sqrt(outX * outX + outY * outY);
      final ix = inX / inLength,
          iy = inY / inLength,
          ox = outX / outLength,
          oy = outY / outLength;
      final turn = math.atan2(ix * oy - iy * ox, ix * ox + iy * oy);
      if (turn.abs() < .001) {
        result.add(b);
        continue;
      }
      final tangent = math.tan(turn.abs() / 2);
      final cut = math.min(
        radius * tangent,
        math.min(inLength, outLength) * .45,
      );
      final r = cut / tangent;
      final entry = (x: b.x - ix * cut, y: b.y - iy * cut);
      final center = (
        x: entry.x - iy * turn.sign * r,
        y: entry.y + ix * turn.sign * r,
      );
      final start = math.atan2(entry.y - center.y, entry.x - center.x);
      for (var j = 0; j <= 8; j++) {
        final angle = start + turn * j / 8;
        result.add((
          x: center.x + math.cos(angle) * r,
          y: center.y + math.sin(angle) * r,
        ));
      }
    }
    return result;
  }

  double get driveableHalfWidth => width / 2 + 90;

  void _alignStart() {
    double dir(int index) {
      final a = points[index % 512];
      final b = points[(index + 1) % 512];
      return math.atan2(b.y - a.y, b.x - a.x);
    }

    double bend(int index) {
      final delta = dir(index + 1) - dir(index);
      return math.atan2(math.sin(delta), math.cos(delta)).abs();
    }

    const ahead = 28;
    var bestAt = 0;
    var best = double.infinity;
    for (var i = 0; i < 512; i++) {
      var score = 0.0;
      for (var k = 0; k < ahead; k++) {
        score += bend(i + k);
      }
      for (var k = 1; k <= 8; k++) {
        score += bend(i - k) * .4;
      }
      if (score < best) {
        best = score;
        bestAt = i;
      }
    }
    if (bestAt == 0) return;
    final shifted = [for (var i = 0; i <= 512; i++) points[(bestAt + i) % 512]];
    for (var i = 0; i <= 512; i++) {
      points[i] = shifted[i];
    }
  }

  Circuit._variant(
    Circuit source, {
    required bool mirrored,
    required bool reversed,
  }) : name = source.name,
       width = source.width {
    length = source.length;
    minX = source.minX;
    maxX = source.maxX;
    minY = source.minY;
    maxY = source.maxY;
    points = [
      for (var i = 0; i <= 512; i++)
        (
          x: mirrored
              ? minX + maxX - source.points[reversed ? (512 - i) % 512 : i].x
              : source.points[reversed ? (512 - i) % 512 : i].x,
          y: source.points[reversed ? (512 - i) % 512 : i].y,
        ),
    ];
  }

  Circuit variant({bool mirrored = false, bool reversed = false}) =>
      mirrored || reversed
      ? Circuit._variant(this, mirrored: mirrored, reversed: reversed)
      : this;

  TrackPoint point(double angle) {
    final position = (angle / (2 * math.pi) % 1) * 512;
    final index = position.floor();
    final t = position - index;
    final a = points[index], b = points[index + 1];
    return (x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t);
  }

  double heading(double angle) {
    final a = point(angle - .004), b = point(angle + .004);
    return math.atan2(b.y - a.y, b.x - a.x);
  }

  double height(double angle) => 1;
  double surfaceHeight(double x, double y) => 1;

  bool overlapsRoad({double margin = 0}) {
    final half = (width + margin) / 2;
    final edges = <(TrackPoint, TrackPoint)>[];
    for (final side in [-1, 1]) {
      final boundary = [
        for (var i = 0; i < 512; i++)
          (
            x: points[i].x - math.sin(heading(i * math.pi / 256)) * half * side,
            y: points[i].y + math.cos(heading(i * math.pi / 256)) * half * side,
          ),
      ];
      for (var i = 0; i < 512; i++) {
        edges.add((boundary[i], boundary[(i + 1) % 512]));
      }
    }
    double cross(TrackPoint a, TrackPoint b, TrackPoint c) =>
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    for (var i = 0; i < edges.length; i++) {
      final (a, b) = edges[i];
      for (var j = i + 1; j < edges.length; j++) {
        final (c, d) = edges[j];
        if (math.max(a.x, b.x) < math.min(c.x, d.x) ||
            math.max(c.x, d.x) < math.min(a.x, b.x) ||
            math.max(a.y, b.y) < math.min(c.y, d.y) ||
            math.max(c.y, d.y) < math.min(a.y, b.y)) {
          continue;
        }
        if (cross(a, b, c) * cross(a, b, d) < -1e-8 &&
            cross(c, d, a) * cross(c, d, b) < -1e-8) {
          return true;
        }
      }
    }
    return false;
  }

  ({double angle, double distance}) nearest(
    double x,
    double y, {
    double? nearAngle,
  }) {
    var closest = double.infinity;
    var angle = 0.0;
    final center = nearAngle == null
        ? 0
        : (nearAngle / (2 * math.pi) * 512).round();
    final start = nearAngle == null ? 0 : center - 16;
    final end = nearAngle == null ? 512 : center + 17;
    for (var segment = start; segment < end; segment++) {
      final i = segment % 512;
      final a = points[i], b = points[i + 1];
      final dx = b.x - a.x, dy = b.y - a.y;
      final squared = dx * dx + dy * dy;
      if (squared < .00001) continue;
      final t = (((x - a.x) * dx + (y - a.y) * dy) / squared).clamp(0.0, 1.0);
      final offsetX = x - a.x - dx * t, offsetY = y - a.y - dy * t;
      final distance = offsetX * offsetX + offsetY * offsetY;
      if (distance < closest) {
        closest = distance;
        angle = (i + t) * math.pi / 256;
      }
    }
    return (angle: angle, distance: math.sqrt(closest));
  }
}
