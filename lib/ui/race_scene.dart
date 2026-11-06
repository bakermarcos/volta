import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as s;
import 'package:vector_math/vector_math.dart' as v;

import '../game/race.dart';
import 'track.dart';

class RaceScene extends StatefulWidget {
  const RaceScene({
    super.key,
    this.race,
    this.circuit,
    this.onAdvance,
    this.approach = 1,
    this.tvMode = false,
  });
  final ValueChanged<double>? onAdvance;
  final double approach;
  final bool tvMode;
  final Race? race;
  final Circuit? circuit;
  @override
  State<RaceScene> createState() => _RaceSceneState();
}

class _RaceSceneState extends State<RaceScene> {
  s.Scene? _scene;
  String? _error;
  final _karts = <int, _Kart>{};
  late final _hud = _PlayerHud(
    () => widget.race,
    _overlay,
    tvMode: () => widget.tvMode,
  );
  double _hudElapsed = 0;
  final _clouds = <s.Node>[];
  late final Race _preview;
  Circuit get _circuit => (widget.race ?? _preview).circuit;
  final _playerCameras = <String, s.PerspectiveCamera>{};
  bool _capturing = false;
  int _frames = 0;
  final _overlay = ValueNotifier<int>(0);
  final _camera = s.PerspectiveCamera(
    position: v.Vector3(33, 39, -42),
    target: v.Vector3(0, 0, 0),
    fovRadiansY: .78,
  );
  final _materials = <int, s.PhysicallyBasedMaterial>{};

  @override
  void initState() {
    super.initState();
    _preview = Race([
      for (var i = 0; i < maxPlayers; i++) Driver('preview-$i', 'Piloto', i),
    ], circuit: widget.circuit ?? Circuit.island);
    _load();
  }

  @override
  void didUpdateWidget(RaceScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.race != widget.race && _scene != null) {
      _playerCameras.clear();
      _tick(Duration.zero, 0);
    }
  }

  Future<void> _load() async {
    try {
      await s.Scene.initializeStaticResources();
      if (!mounted) return;
      final scene = s.Scene();
      _scene = scene;
      scene.directionalLight = s.DirectionalLight(
        direction: v.Vector3(-.5, -1, .3),
        intensity: 2.5,
        castsShadow: true,
        shadowCasterFaces: s.ShadowCasterFaces.back,
        shadowCascadeCount: 1,
        shadowMapResolution: 1024,
      );
      scene.environmentSettings = s.EnvironmentSettings(
        toneMapping: s.ToneMappingMode.aces,
        exposure: .9,
        colorGradingEnabled: true,
        saturation: 1.2,
        contrast: 1.08,
        bloomEnabled: true,
        bloomThreshold: 1.1,
        bloomIntensity: .16,
        bloomScatter: .7,
        vignetteEnabled: true,
        vignetteIntensity: .16,
      );
      _buildIsland(scene);
      _tick(Duration.zero, 0);
      setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível iniciar o 3D: $error');
      }
    }
  }

  s.PhysicallyBasedMaterial _material(
    int color,
  ) => _materials.putIfAbsent(color, () {
    final c = Color(color);
    double linear(double x) =>
        x <= .04045 ? x / 12.92 : math.pow((x + .055) / 1.055, 2.4).toDouble();
    return s.PhysicallyBasedMaterial()
      ..baseColorFactor = v.Vector4(linear(c.r), linear(c.g), linear(c.b), 1)
      ..roughnessFactor = .75;
  });
  s.Node _mesh(
    s.Geometry geometry,
    int color,
    double x,
    double y,
    double z, {
    s.Node? parent,
    String name = '',
  }) {
    final node = s.Node(name: name, mesh: s.Mesh(geometry, _material(color)))
      ..position = v.Vector3(x, y, z)
      ..shadowStatic = parent == null;
    (parent ?? _scene!.root).add(node);
    return node;
  }

  s.Node _box(
    double x,
    double y,
    double z,
    double w,
    double h,
    double d,
    int color, {
    s.Node? parent,
  }) => _mesh(
    s.CuboidGeometry(v.Vector3(w, h, d)),
    color,
    x,
    y,
    z,
    parent: parent,
  );

  void _road(
    double left,
    double right,
    double lift,
    int color, {
    bool striped = false,
  }) {
    const count = 512;
    final positions = <double>[], colors = <double>[];
    final indices = <int>[];
    for (var i = 0; i < count; i++) {
      final base = positions.length ~/ 3;
      final c = Color(striped && (i ~/ 3).isEven ? 0xFFFDF2CF : color);
      for (final angle in [
        i * math.pi * 2 / count,
        (i + 1) * math.pi * 2 / count,
      ]) {
        final point = _circuit.point(angle), heading = _circuit.heading(angle);
        for (final lane in [left, right]) {
          positions.addAll([
            (point.x - math.sin(heading) * lane) / 20,
            (_circuit.height(angle) + lift) / 20,
            (point.y + math.cos(heading) * lane) / 20,
          ]);
          colors.addAll([
            math.pow(c.r, 2.2).toDouble(),
            math.pow(c.g, 2.2).toDouble(),
            math.pow(c.b, 2.2).toDouble(),
            1,
          ]);
        }
      }
      indices.addAll([base, base + 1, base + 2, base + 1, base + 3, base + 2]);
    }
    final material = s.PhysicallyBasedMaterial()
      ..roughnessFactor = .95
      ..depthLayer = striped ? (left < 0 ? 2 : 3) : 1;
    final node = s.Node(
      name: 'track-$left-$right',
      mesh: s.Mesh(
        s.MeshGeometry.fromArrays(
          positions: Float32List.fromList(positions),
          colors: Float32List.fromList(colors),
          indices: indices,
        ),
        material,
      ),
    );
    node.shadowStatic = true;
    _scene!.add(node);
  }

  void _buildIsland(s.Scene scene) {
    final sea = _mesh(
      s.PlaneGeometry(width: 10000, depth: 10000),
      0xFF70C9DF,
      0,
      -2.1,
      0,
      name: 'lagoon',
    );
    sea.mesh = s.Mesh(
      sea.mesh!.primitives.single.geometry,
      s.UnlitMaterial()..baseColorFactor = v.Vector4(.16, .5, .62, 1),
    );
    sea.shadowCastingMode = s.ShadowCastingMode.off;
    final island = _mesh(
      s.CylinderGeometry(
        topRadius: 26,
        bottomRadius: 22,
        height: 2.5,
        radialSegments: 64,
      ),
      0xFFF0CD98,
      0,
      -1.5,
      0,
      name: 'island',
    );
    island.scale = v.Vector3(
      (math.max(_circuit.minX.abs(), _circuit.maxX.abs()) +
              _circuit.width * 2) /
          20 /
          25.7 *
          math.sqrt2,
      1,
      (math.max(_circuit.minY.abs(), _circuit.maxY.abs()) +
              _circuit.width * 2) /
          20 /
          25.7 *
          math.sqrt2,
    );
    final grass = _mesh(
      s.CylinderGeometry(
        topRadius: 25.7,
        bottomRadius: 26,
        height: .3,
        radialSegments: 64,
      ),
      0xFF88C86B,
      0,
      -.1,
      0,
      name: 'grass',
    );
    grass.scale = island.scale;
    _road(-_circuit.width / 2, _circuit.width / 2, 0, 0xFF53586D);
    _road(
      -_circuit.width / 2 - 5,
      -_circuit.width / 2,
      0,
      0xFFFF7186,
      striped: true,
    );
    _road(
      _circuit.width / 2,
      _circuit.width / 2 + 5,
      0,
      0xFFFF7186,
      striped: true,
    );
    final marks = s.InstancedMesh(
      geometry: s.PlaneGeometry(width: .08, depth: .55),
      material: _material(0xFFE8DFAA)..depthLayer = 4,
      cullInstances: true,
    );
    final markCount = (_circuit.length / 35).round();
    for (var i = 0; i < markCount; i++) {
      final a = i * math.pi * 2 / markCount;
      final p = _circuit.point(a);
      marks.addInstance(
        v.Matrix4.compose(
          v.Vector3(p.x / 20, _circuit.height(a) / 20 + .002, p.y / 20),
          v.Quaternion.axisAngle(
            v.Vector3(0, 1, 0),
            math.pi / 2 - _circuit.heading(a),
          ),
          v.Vector3.all(1),
        ),
      );
    }
    _scene!.add(
      s.Node(name: 'center-marks')
        ..shadowStatic = true
        ..shadowCastingMode = s.ShadowCastingMode.off
        ..addComponent(s.InstancedMeshComponent(marks)),
    );
    final posts = s.InstancedMesh(
      geometry: s.CuboidGeometry(v.Vector3(.18, .7, .18)),
      material: _material(0xFFFFFFFF),
      cullInstances: true,
    );
    final postCount = (_circuit.length / 140).round();
    for (var i = 0; i < postCount; i++) {
      final angle = i * math.pi * 2 / postCount,
          p = _circuit.point(angle),
          h = _circuit.heading(angle);
      for (final side in [-1, 1]) {
        final offset = side * _circuit.driveableHalfWidth,
            x = p.x - math.sin(h) * offset,
            y = p.y + math.cos(h) * offset;
        if (_circuit.nearest(x, y).distance < _circuit.width / 2 + 8) continue;
        posts.addInstance(
          v.Matrix4.translationValues(x / 20, .4, y / 20),
          color: i.isEven
              ? v.Vector4(.5, .9, .15, 1)
              : v.Vector4(.9, .9, .85, 1),
        );
      }
    }
    _scene!.add(
      s.Node(name: 'roadside-posts')
        ..shadowStatic = true
        ..addComponent(s.InstancedMeshComponent(posts)),
    );
    final start = _circuit.point(0), heading = _circuit.heading(0);
    for (var lane = 0; lane < 10; lane++) {
      for (var row = 0; row < 3; row++) {
        final side =
                -_circuit.width / 2 +
                _circuit.width / 20 +
                lane * _circuit.width / 10,
            advance = row * 5.0;
        final tile = _box(
          (start.x - math.sin(heading) * side + math.cos(heading) * advance) /
              20,
          _circuit.height(0) / 20 + .0125,
          (start.y + math.cos(heading) * side + math.sin(heading) * advance) /
              20,
          _circuit.width / 200,
          .025,
          .25,
          (lane + row).isEven ? 0xFFFAF4DE : 0xFF202C3B,
        );
        for (final primitive in tile.mesh!.primitives) {
          primitive.material.depthLayer = 5;
        }
        tile.rotation = v.Quaternion.axisAngle(
          v.Vector3(0, 1, 0),
          math.pi / 2 - heading,
        );
      }
    }
    for (final lane in [-_circuit.width / 2 - 15, _circuit.width / 2 + 15]) {
      final x = (start.x - math.sin(heading) * lane) / 20,
          z = (start.y + math.cos(heading) * lane) / 20;
      _box(x, 2.35, z, .22, 4.6, .22, 0xFFFAF4DE);
      final flag = _box(x, 4.5, z, .15, .7, 1.3, 0xFFFF7186);
      flag.rotation = v.Quaternion.axisAngle(
        v.Vector3(0, 1, 0),
        math.pi / 2 - heading,
      );
    }
    final arch = _box(
      start.x / 20,
      4.65,
      start.y / 20,
      (_circuit.width + 40) / 20,
      .6,
      .45,
      0xFF8B62D9,
    );
    arch.rotation = v.Quaternion.axisAngle(
      v.Vector3(0, 1, 0),
      math.pi / 2 - heading,
    );
    final random = math.Random(19);
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      final p = _circuit.point(angle);
      final heading = _circuit.heading(angle);
      final side = (i.isEven ? -1 : 1) * (_circuit.driveableHalfWidth + 40);
      final x = (p.x - math.sin(heading) * side) / 20,
          z = (p.y + math.cos(heading) * side) / 20;
      if (i == 0 || i == 1 || i == 23) continue;
      if (_circuit.nearest(x * 20, z * 20).distance < _circuit.width * .8) {
        continue;
      }
      final h = i.isEven
          ? 1.5 + random.nextDouble() * .5
          : 1.1 + random.nextDouble() * .4;
      _mesh(
        s.CylinderGeometry(
          topRadius: .12,
          bottomRadius: .2,
          height: h,
          radialSegments: 7,
        ),
        0xFF996F56,
        x,
        h / 2 + .05,
        z,
      );
      final crown = _mesh(
        s.IcosphereGeometry(radius: h * .65, subdivisions: 1),
        i.isEven ? 0xFF45A86B : 0xFFB2D86C,
        x,
        h + .35,
        z,
      );
      crown.scale = v.Vector3(1, 1.1, 1);
    }
    if (_circuit == Circuit.island) {
      // A small windmill gives the shared camera a recognizable infield landmark.
      _box(-4, 1.35, 0, 2.8, 2.6, 2.8, 0xFFF9D899);
      _mesh(
        s.CylinderGeometry(
          topRadius: 0,
          bottomRadius: 2.2,
          height: 1.6,
          radialSegments: 4,
        ),
        0xFFFF7B88,
        -4,
        3.3,
        0,
      );
    }
    for (var i = 0; i < 7; i++) {
      final cloud = s.Node(name: 'cloud-$i')
        ..position = v.Vector3(
          -35 + i * 11,
          8 + (i % 3) * 2.0,
          21 + (i % 2) * 5.0,
        );
      scene.add(cloud);
      for (var j = -1; j <= 1; j++) {
        final puff = _mesh(
          s.IcosphereGeometry(radius: j == 0 ? 1.8 : 1.2, subdivisions: 1),
          0xFFF9F8F1,
          j * 1.5,
          0,
          0,
          parent: cloud,
        );
        puff.scale = v.Vector3(1.4, .65, 1);
      }
      _clouds.add(cloud);
    }
  }

  late final s.Geometry _wheelGeometry = _makeWheelGeometry();

  s.Geometry _makeWheelGeometry() {
    final positions = <double>[], colors = <double>[];
    void triangle(v.Vector3 a, v.Vector3 b, v.Vector3 c, double shade) {
      for (final p in [a, b, c]) {
        positions.addAll([p.x, p.y, p.z]);
        colors.addAll([shade, shade, shade, 1]);
      }
    }

    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12, b = (i + 1) * math.pi / 12;
      v.Vector3 point(double angle, double radius, double y) =>
          v.Vector3(math.cos(angle) * radius, y, math.sin(angle) * radius);
      final lowA = point(a, .28, -.125), lowB = point(b, .28, -.125);
      final highA = point(a, .28, .125), highB = point(b, .28, .125);
      const tread = .025;
      triangle(lowA, highA, lowB, tread);
      triangle(lowB, highA, highB, tread);
      for (final side in [-1.0, 1.0]) {
        final y = side * .125;
        final innerA = point(a, .1, y), innerB = point(b, .1, y);
        final outerA = point(a, .28, y), outerB = point(b, .28, y);
        void cap(v.Vector3 p, v.Vector3 q, v.Vector3 r, double shade) {
          if (side > 0) {
            triangle(p, r, q, shade);
          } else {
            triangle(p, q, r, shade);
          }
        }

        cap(v.Vector3(0, y, 0), innerA, innerB, .4);
        final spoke = i % 6 == 0 ? .32 : .025;
        cap(innerA, outerA, innerB, spoke);
        cap(innerB, outerA, outerB, spoke);
      }
    }
    return s.MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      colors: Float32List.fromList(colors),
      indices: List.generate(positions.length ~/ 3, (i) => i),
    );
  }

  _Kart _kart(Car car) {
    final root = s.Node(name: 'kart-${car.driver.slot}');
    _scene!.add(root);
    final body = s.Node();
    root.add(body);
    _box(0, .35, 0, 1.1, .35, 1.8, car.driver.color, parent: body);
    _box(0, .28, .95, 1.25, .2, .25, 0xFF263342, parent: body);
    _box(0, .6, -.32, .6, .55, .65, 0xFF263342, parent: body);
    _box(0, .55, .58, .78, .2, .65, car.driver.color, parent: body);
    _mesh(
      s.SphereGeometry(radius: .29, segments: 12, rings: 8),
      car.driver.color,
      0,
      1.05,
      -.15,
      parent: body,
    );
    _box(0, 1.08, .105, .43, .14, .13, 0xFF263342, parent: body);
    final wheels = <s.Node>[];
    for (final x in [-.64, .64]) {
      for (final z in [-.6, .58]) {
        final wheel = _mesh(
          _wheelGeometry,
          0xFFFFFFFF,
          x,
          .28,
          z,
          parent: root,
        );
        wheel.rotation = v.Quaternion.axisAngle(
          v.Vector3(0, 0, 1),
          math.pi / 2,
        );
        wheels.add(wheel);
      }
    }
    final flame = _mesh(
      s.IcosphereGeometry(radius: .35, subdivisions: 1),
      0xFFFFD061,
      0,
      .35,
      -1.3,
      parent: root,
    );
    flame.visible = false;
    return _Kart(root, body, wheels, flame);
  }

  void _tick(Duration elapsed, double dt) {
    widget.onAdvance?.call(dt);
    final race = widget.race ?? _preview;
    final seconds = elapsed.inMicroseconds / 1000000;
    final slots = race.cars.map((c) => c.driver.slot).toSet();
    for (final entry in _karts.entries) {
      entry.value.root.visible = slots.contains(entry.key);
    }
    for (final car in race.cars) {
      final kart = _karts.putIfAbsent(car.driver.slot, () => _kart(car));
      final height = _circuit.surfaceHeight(car.x, car.y) / 20;
      final position = v.Vector3(car.x / 20, height, car.y / 20);
      final motion = (car.speed.abs() / 270).clamp(0.0, 1.0);
      kart.root.position = position;
      kart.root.rotation = v.Quaternion.axisAngle(
        v.Vector3(0, 1, 0),
        math.pi / 2 - car.heading,
      );
      kart.body.rotation = v.Quaternion.axisAngle(
        v.Vector3(0, 0, 1),
        -.1 * car.steering * (car.speed / 270),
      );
      kart.body.position = v.Vector3(
        0,
        math.sin(seconds * 18 + car.driver.slot) * .012 * motion,
        0,
      );
      kart.spin = (kart.spin + dt * car.speed / 22) % (math.pi * 2);
      for (final (index, wheel) in kart.wheels.indexed) {
        wheel.rotation =
            v.Quaternion.axisAngle(
              v.Vector3(0, 1, 0),
              index.isOdd ? car.steering * .3 : 0,
            ) *
            v.Quaternion.axisAngle(v.Vector3(0, 0, 1), math.pi / 2) *
            v.Quaternion.axisAngle(v.Vector3(0, 1, 0), kart.spin);
      }
      kart.flame.visible = car.boosting;
      kart.flame.scale = v.Vector3(.8, .8, 2.2 + math.sin(seconds * 55) * .7);
    }
    for (var i = 0; i < _clouds.length; i++) {
      _clouds[i].position = v.Vector3(
        -35 + i * 11 + math.sin(seconds * .13 + i) * 1.6,
        8 + (i % 3) * 2.0,
        21 + (i % 2) * 5.0,
      );
    }
    if (widget.race == null) {
      final overview = s.PerspectiveCamera.framing(
        v.Aabb3.minMax(
          v.Vector3(_circuit.minX / 20 - 5, 0, _circuit.minY / 20 - 5),
          v.Vector3(_circuit.maxX / 20 + 5, 5, _circuit.maxY / 20 + 5),
        ),
        direction: v.Vector3(.6, .85, -1),
        margin: 1.1,
        fovRadiansY: .78,
      );
      _camera.position =
          overview.target + (overview.position - overview.target) * .7;
      _camera.target = overview.target;
    }
    for (final car in race.cars) {
      final height = _circuit.surfaceHeight(car.x, car.y) / 20;
      final target = v.Vector3(
        car.x / 20 + math.cos(car.heading) * 3,
        height + .7,
        car.y / 20 + math.sin(car.heading) * 3,
      );
      final approach = widget.approach.clamp(0.0, 1.0);
      final eye = v.Vector3(
        car.x / 20 - math.cos(car.heading) * (6 + (1 - approach) * 16),
        height + 2.8 + (1 - approach) * 9,
        car.y / 20 - math.sin(car.heading) * (6 + (1 - approach) * 16),
      );
      final camera = _playerCameras.putIfAbsent(
        car.driver.id,
        () => s.PerspectiveCamera(
          position: eye.clone(),
          target: target.clone(),
          fovRadiansY: 1.0,
        ),
      );
      final blend = 1 - math.exp(-dt.clamp(0.0, .05) * 5);
      camera.position += (eye - camera.position) * blend;
      camera.target += (target - camera.target) * blend;
      camera.fovRadiansY +=
          (1.0 +
              .12 * (car.speed.abs() / 270).clamp(0, 1) +
              (car.boosting ? .06 : 0) -
              camera.fovRadiansY) *
          blend;
    }
    _hudElapsed += dt;
    if (_hudElapsed >= 1 / 30 || dt == 0) {
      _hudElapsed = 0;
      _overlay.value++;
    }
    _frames++;
    const capture = String.fromEnvironment('VOLTA_CAPTURE');
    if (capture.isNotEmpty && _frames == 90 && !_capturing) {
      _capturing = true;
      _capture(capture);
    }
  }

  List<s.RenderView> _views(Duration elapsed) {
    final race = widget.race;
    if (race == null) return [s.RenderView(camera: _camera)];
    final rectangles = playerViewports(race.cars.length);
    return [
      for (var i = 0; i < race.cars.length; i++)
        s.RenderView(
          camera: _playerCameras[race.cars[i].driver.id] ?? _camera,
          viewport: rectangles[i],
        ),
    ];
  }

  Future<void> _capture(String path) async {
    await s.Scene.preload();
    Future<void> save(s.Camera? camera, String name) async {
      const size = ui.Size(1400, 900);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const Color(0xFF97D9E6), ui.BlendMode.src);
      if (camera == null) {
        _scene!.renderViews(
          _views(Duration.zero),
          canvas,
          region: ui.Offset.zero & size,
          pixelRatio: 1,
        );
        _hud.paint(canvas, size);
      } else {
        _scene!.render(
          camera,
          canvas,
          viewport: ui.Offset.zero & size,
          pixelRatio: 1,
        );
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      debugPrint('VOLTA 3D capture: ${file.path}');
    }

    final name = File(path).uri.pathSegments.last;
    await save(_camera, name);
    final leader = (widget.race ?? _preview).standings.first;
    final height =
        _circuit.height(_circuit.nearest(leader.x, leader.y).angle) / 20;
    final chase = s.PerspectiveCamera(
      position: v.Vector3(
        leader.x / 20 - math.cos(leader.heading) * 9,
        height + 5.9,
        leader.y / 20 - math.sin(leader.heading) * 9,
      ),
      target: v.Vector3(
        leader.x / 20 + math.cos(leader.heading) * 3,
        height + .6,
        leader.y / 20 + math.sin(leader.heading) * 3,
      ),
      fovRadiansY: .78,
    );
    await save(chase, name.replaceFirst('.png', '-chase.png'));
    if (widget.race != null) {
      await save(null, name.replaceFirst('.png', '-split.png'));
    }
    final report = await _scene!.probeDepthConflicts(camera: chase);
    debugPrint(
      'VOLTA depth probe: ${report.conflicts.length} conflicts at ${report.width}x${report.height}',
    );
    for (final conflict in report.conflicts) {
      debugPrint(conflict.describe());
    }
  }

  @override
  void dispose() {
    _hud.disposeText();
    _overlay.dispose();
    _scene?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
    }
    if (_scene == null) {
      return const Center(child: CircularProgressIndicator(color: lime));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.race == null ? 24 : 0),
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF97D9E6))),
          Positioned.fill(
            child: s.SceneView(
              _scene!,
              viewsBuilder: _views,
              onTick: _tick,
              maxFrameRate: widget.race == null ? 30 : 60,
              warmUp: true,
              pixelRatio: Platform.isAndroid ? .8 : 1,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(child: CustomPaint(painter: _hud)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kart {
  _Kart(this.root, this.body, this.wheels, this.flame);
  final s.Node root, body, flame;
  final List<s.Node> wheels;
  double spin = 0;
}

List<Rect> playerViewports(int count) {
  if (count < 1 || count > maxPlayers) {
    throw RangeError.range(count, 1, maxPlayers);
  }
  if (count == 1) return [const Rect.fromLTWH(0, 0, 1, 1)];
  final topCount = count == 2
      ? 1
      : count <= 4
      ? 2
      : 3;
  final bottomCount = count - topCount;
  return [
    for (var i = 0; i < topCount; i++)
      Rect.fromLTWH(i / topCount, 0, 1 / topCount, .5),
    for (var i = 0; i < bottomCount; i++)
      Rect.fromLTWH(i / bottomCount, .5, 1 / bottomCount, .5),
  ];
}

class _PlayerHud extends CustomPainter {
  _PlayerHud(this.race, ChangeNotifier repaint, {required this.tvMode})
    : super(repaint: repaint);
  final Race? Function() race;
  final bool Function() tvMode;
  final _textPainters = <TextPainter>[];
  int _textIndex = 0;
  void disposeText() {
    for (final painter in _textPainters) {
      painter.dispose();
    }
  }

  void _text(
    Canvas canvas,
    String value,
    Offset position,
    double size,
    Color color,
  ) {
    if (_textIndex == _textPainters.length) {
      _textPainters.add(TextPainter(textDirection: TextDirection.ltr));
    }
    final painter = _textPainters[_textIndex++];
    if (painter.text?.toPlainText() != value ||
        painter.text?.style?.fontSize != size ||
        painter.text?.style?.color != color) {
      painter.text = TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: ink, blurRadius: 4)],
        ),
      );
      painter.layout();
    }
    painter.paint(canvas, position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _textIndex = 0;
    final current = race();
    if (current == null) return;
    final rectangles = playerViewports(current.cars.length);
    final standings = current.standings;
    for (var i = 0; i < current.cars.length; i++) {
      final car = current.cars[i], fraction = rectangles[i];
      final rect = Rect.fromLTWH(
        fraction.left * size.width,
        fraction.top * size.height,
        fraction.width * size.width,
        fraction.height * size.height,
      );
      canvas.save();
      canvas.clipRect(rect);
      canvas.drawRect(
        rect.deflate(1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ink,
      );
      final scale = (rect.width / 400).clamp(tvMode() ? 1.15 : .9, 1.8);
      final insetX = rect.width * .05, insetY = rect.height * .05;
      canvas.translate(rect.left + insetX, rect.top + insetY);
      canvas.scale(scale);
      final hud = Rect.fromLTWH(
        0,
        0,
        (rect.width - insetX * 2) / scale,
        (rect.height - insetY * 2) / scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, 138, 66),
          const Radius.circular(10),
        ),
        Paint()..color = ink.withValues(alpha: .78),
      );
      final color = Color(car.driver.color);
      _text(
        canvas,
        car.driver.name,
        hud.topLeft + const Offset(10, 8),
        15,
        color,
      );
      _text(
        canvas,
        '${standings.indexOf(car) + 1}º',
        hud.topLeft + const Offset(10, 30),
        25,
        Colors.white,
      );
      _text(
        canvas,
        '${math.min(car.laps + 1, current.totalLaps)}/${current.totalLaps}',
        Offset(hud.right - 46, hud.top + 10),
        16,
        Colors.white,
      );
      _text(
        canvas,
        car.retired
            ? 'SAIU'
            : car.finishedAt != null
            ? 'CHEGOU'
            : '${car.speed.abs().round()}',
        Offset(hud.left + 10, hud.bottom - 32),
        20,
        Colors.white,
      );
      _text(
        canvas,
        'CORRIDA ${formatRaceTime(car.raceTime(current.elapsed))}',
        Offset(hud.right - 150, hud.top + 34),
        13,
        Colors.white,
      );
      _text(
        canvas,
        'VOLTA ${formatRaceTime(car.lapTime(current.elapsed))}',
        Offset(hud.right - 150, hud.top + 53),
        13,
        Colors.white,
      );
      if (car.finishedAt == null && !car.retired && car.speed.abs() > 30) {
        final track = current.circuit.heading(car.trackAngle);
        final delta = math.atan2(
          math.sin(car.heading - track),
          math.cos(car.heading - track),
        );
        if (delta.abs() > math.pi / 2) {
          _text(
            canvas,
            'CONTRA MÃO',
            Offset(hud.left + 10, hud.bottom - 54),
            16,
            const Color(0xFFFF7186),
          );
        }
      }
      if (car.finishedAt != null) {
        _text(
          canvas,
          '${standings.indexOf(car) + 1}º · CHEGOU!',
          Offset(hud.width / 2 - 85, hud.height * .32),
          22,
          color,
        );
        _text(
          canvas,
          formatRaceTime(car.finishedAt!),
          Offset(hud.width / 2 - 52, hud.height * .32 + 30),
          20,
          Colors.white,
        );
      }
      final bar = Rect.fromLTWH(hud.right - 94, hud.bottom - 22, 80, 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(3)),
        Paint()..color = ink,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            bar.left,
            bar.top,
            bar.width * car.boostCharge,
            bar.height,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = car.boosting ? const Color(0xFFFFD061) : color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PlayerHud oldDelegate) => true;
}
