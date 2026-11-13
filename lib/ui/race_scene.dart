import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _presented = false;
  late final _hud = _PlayerHud(
    () => widget.race,
    _overlay,
    tvMode: () => widget.tvMode,
    presented: () => _presented,
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
  final _materials = <int, s.UnlitMaterial>{};
  s.Texture2D? _smokeTexture;
  s.SpriteMaterial? _smokeMaterial;
  s.Node? _helmet, _newKart;
  Uint8List? _oobiPixels;
  var _oobiSize = 0;
  final _oobiTints = <int, s.Texture2D>{};
  s.Geometry? _wheelGeometry;
  s.UnlitMaterial? _wheelMaterial;

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
      _dropKarts();
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
      final android = Platform.isAndroid;
      scene.directionalLight = s.DirectionalLight(
        direction: v.Vector3(-.5, -1, .3),
        intensity: 2.4,
        castsShadow: !android,
        shadowCasterFaces: s.ShadowCasterFaces.back,
        shadowCascadeCount: 1,
        shadowMapResolution: 1024,
        shadowDepthBias: .08,
        shadowNormalBias: .08,
      );
      scene.environmentSettings = s.EnvironmentSettings(
        toneMapping: s.ToneMappingMode.aces,
        exposure: .92,
        colorGradingEnabled: !android,
        saturation: 1.2,
        contrast: 1.08,
        bloomEnabled: !android,
        bloomThreshold: 1.1,
        bloomIntensity: .16,
        bloomScatter: .7,
        vignetteEnabled: !android,
        vignetteIntensity: .16,
      );
      _buildIsland(scene);
      _helmet = await s.Node.fromGlbAsset(
        'assets/karts/kart_low_poly.glb',
        maxTextureSize: 512,
      );
      _newKart = await s.Node.fromGlbAsset(
        'assets/karts/kart-oobi.glb',
        maxTextureSize: 512,
      );
      await _loadOobiAtlas();
      _tick(Duration.zero, 0);
      setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível iniciar o 3D: $error');
      }
    }
  }

  s.UnlitMaterial _material(int color) => _materials.putIfAbsent(color, () {
    final c = Color(color);
    double linear(double channel) => channel <= .04045
        ? channel / 12.92
        : math.pow((channel + .055) / 1.055, 2.4).toDouble();
    return s.UnlitMaterial()
      ..baseColorFactor = v.Vector4(linear(c.r), linear(c.g), linear(c.b), 1)
      ..vertexColorWeight = 0;
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
      ..frustumCulled = false
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
    final center = List<({double x, double y, double h})>.generate(count, (i) {
      final angle = i * math.pi * 2 / count;
      final point = _circuit.point(angle);
      return (x: point.x, y: point.y, h: _circuit.heading(angle));
    });
    List<({double x, double y})> side(double lane) {
      final limits = List<double>.filled(count, double.infinity);
      for (var i = 0; i < count; i++) {
        final j = (i + 1) % count;
        final cx = center[j].x - center[i].x, cy = center[j].y - center[i].y;
        final step = math.max(math.sqrt(cx * cx + cy * cy), 1.0);
        final dx =
            center[j].x -
            math.sin(center[j].h) * lane -
            (center[i].x - math.sin(center[i].h) * lane);
        final dy =
            center[j].y +
            math.cos(center[j].h) * lane -
            (center[i].y + math.cos(center[i].h) * lane);
        final len = math.sqrt(dx * dx + dy * dy);
        if (dx * cx + dy * cy >= 0 && len <= step * 2.2) continue;
        final turn = math
            .atan2(
              math.sin(center[j].h - center[i].h),
              math.cos(center[j].h - center[i].h),
            )
            .abs();
        final radius = turn < .02 ? lane.abs() : step / turn * .85;
        limits[i] = math.min(limits[i], radius);
        limits[j] = math.min(limits[j], radius);
      }
      for (var pass = 0; pass < 24; pass++) {
        final next = [...limits];
        for (var i = 0; i < count; i++) {
          final prev = (i + count - 1) % count, nxt = (i + 1) % count;
          final step = math.max(
            math.sqrt(
              math.pow(center[i].x - center[prev].x, 2) +
                  math.pow(center[i].y - center[prev].y, 2),
            ),
            1.0,
          );
          final grow = step * .45;
          next[i] = math.min(
            limits[i],
            math.min(limits[prev] + grow, limits[nxt] + grow),
          );
        }
        for (var i = 0; i < count; i++) {
          limits[i] = next[i];
        }
      }
      return List.generate(count, (i) {
        final reach = math.min(lane.abs(), limits[i]);
        final signed = lane.sign * reach;
        return (
          x: center[i].x - math.sin(center[i].h) * signed,
          y: center[i].y + math.cos(center[i].h) * signed,
        );
      });
    }

    final edges = [side(left), side(right)];
    for (var i = 0; i < count; i++) {
      final base = positions.length ~/ 3;
      final c = Color(striped && (i ~/ 3).isEven ? 0xFFFDF2CF : color);
      final next = (i + 1) % count;
      for (final index in [i, next]) {
        for (final edge in edges) {
          positions.addAll([
            edge[index].x / 20,
            (_circuit.height(index * math.pi * 2 / count) + lift) / 20,
            edge[index].y / 20,
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
    final normals = Float32List(positions.length);
    for (var i = 1; i < normals.length; i += 3) {
      normals[i] = 1;
    }
    final material = s.PhysicallyBasedMaterial()
      ..roughnessFactor = .95
      ..metallicFactor = 0
      ..vertexColorWeight = 1
      ..doubleSided = true
      ..depthLayer = striped ? (left < 0 ? 2 : 3) : 1;
    final node = s.Node(
      name: 'track-$left-$right',
      mesh: s.Mesh(
        s.MeshGeometry.fromArrays(
          positions: Float32List.fromList(positions),
          normals: normals,
          colors: Float32List.fromList(colors),
          indices: indices,
        ),
        material,
      ),
    );
    node.shadowStatic = true;
    node.shadowCastingMode = s.ShadowCastingMode.off;
    node.frustumCulled = false;
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
      -2.05,
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
      0xFF86B072,
      0,
      -.55,
      0,
      name: 'grass',
    );
    grass.scale = island.scale;
    final half = _circuit.width / 2;
    _road(-half, half, 0, 0xFF3E4552);
    _road(-half, -half + 2.5, .35, 0xFF0C0E12);
    _road(half - 2.5, half, .35, 0xFF0C0E12);
    _road(-half - 5, -half, 0, 0xFFFF4D68, striped: true);
    _road(half, half + 5, 0, 0xFFFF4D68, striped: true);
    final marks = s.InstancedMesh(
      geometry: s.PlaneGeometry(width: .08, depth: .55),
      material: _material(0xFFE8DFAA)..depthLayer = 4,
      cullInstances: false,
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
        ..frustumCulled = false
        ..shadowStatic = true
        ..shadowCastingMode = s.ShadowCastingMode.off
        ..addComponent(s.InstancedMeshComponent(marks)),
    );
    final posts = s.InstancedMesh(
      geometry: s.CuboidGeometry(v.Vector3(.18, .7, .18)),
      material: _material(0xFFFFFFFF),
      cullInstances: false,
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
        ..frustumCulled = false
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
        ..frustumCulled = false
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

  s.Geometry _classicWheel() {
    final cached = _wheelGeometry;
    if (cached != null) return cached;
    final positions = <double>[], colors = <double>[];
    void triangle(v.Vector3 a, v.Vector3 b, v.Vector3 c, double shade) {
      for (final p in [a, b, c]) {
        positions.addAll([p.x, p.y, p.z]);
        colors.addAll([shade, shade, shade, 1]);
      }
    }
    if (node.name == 'Volante') node.position = v.Vector3(0, .56, .18);
    if (node.name == 'Coluna do volante') {
      node.position = v.Vector3(0, .42, .08);
    }
    if (node.name == 'Viseira') node.position = v.Vector3(0, .02, .2);
    if (node.name == 'Brilho da viseira') {
      node.position = v.Vector3(.05, .06, .23);
      node.scale = v.Vector3(.7, .7, .5);
    }
    for (final child in node.children) {
      _paintKart(child, tint);
    }
    return _wheelGeometry = s.MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      colors: Float32List.fromList(colors),
      indices: List.generate(positions.length ~/ 3, (i) => i),
    );
  }

  _Kart _kart(Car car) {
    final root = s.Node(name: 'kart-${car.driver.slot}')..frustumCulled = false;
    _scene!.add(root);
    final body = s.Node()..frustumCulled = false;
    root.add(body);
    final style = car.driver.model;
    if (style == 2 && _newKart != null) {
      return _characterKart(root, body, car.driver.color);
    }
    if (style != 1 && _helmet != null) return _helmetKart(root, body, car);
    final color = car.driver.color;
    _box(0, .35, 0, 1.1, .35, 1.8, color, parent: body);
    _box(0, .28, .95, 1.25, .2, .25, 0xFF263342, parent: body);
    _box(0, .6, -.32, .6, .55, .65, 0xFF263342, parent: body);
    _box(0, .55, .58, .78, .2, .65, color, parent: body);
    _mesh(
      s.SphereGeometry(radius: .29, segments: 12, rings: 8),
      color,
      0,
      1.05,
      -.15,
      parent: body,
    );
    _box(0, 1.08, .105, .43, .14, .13, 0xFF263342, parent: body);
    final material = _wheelMaterial ??= s.UnlitMaterial()
      ..baseColorFactor = v.Vector4(1, 1, 1, 1)
      ..vertexColorWeight = 1;
    final wheels = [
      for (final (x, z) in [(-.64, .58), (.64, .58), (-.64, -.6), (.64, -.6)])
        s.Node(mesh: s.Mesh(_classicWheel(), material))
          ..position = v.Vector3(x, .28, z)
          ..frustumCulled = false,
    ];
    for (final wheel in wheels) {
      body.add(wheel);
    }
    final flame = _mesh(
      s.IcosphereGeometry(radius: .35, subdivisions: 1),
      0xFFFFD061,
      0,
      .35,
      -1.3,
      parent: body,
    )..visible = false;
    final smoke = <_TireSmoke>[
      for (final (index, side) in [-1.0, 1.0].indexed)
        _smoke(
          body,
          side,
          at: wheels[index + 2].position + v.Vector3(0, .04, 0),
        ),
    ];
    return _Kart(root, body, wheels, [flame], smoke, style: 1);
  }

  _Kart _helmetKart(s.Node root, s.Node body, Car car) {
    final mesh = _helmet!.clone();
    _faceTrack(mesh, .98);
    _paintHelmet(mesh, car.driver.color);
    body.add(mesh);
    final wheels = [
      for (final name in [
        'Roda Frente E',
        'Roda Frente D',
        'Roda Tras E',
        'Roda Tras D',
      ])
        mesh.getChildByName(name)!,
    ];
    final flame = _mesh(
      s.IcosphereGeometry(radius: .35, subdivisions: 1),
      0xFFFFD061,
      0,
      .4,
      -1.15,
      parent: mesh,
    )..visible = false;
    final smoke = <_TireSmoke>[
      for (final (index, side) in [-1.0, 1.0].indexed)
        _smoke(
          mesh,
          side,
          at: wheels[index + 2].position + v.Vector3(0, .04, 0),
        ),
    ];
    return _Kart(root, body, wheels, [flame], smoke, style: 0);
  }

  void _paintHelmet(s.Node node, int color) {
    const names = {
      'Carenagem dianteira',
      'Lateral E',
      'Lateral D',
      'Aerofolio',
      'Capacete',
      'Cubo',
    };
    if (names.contains(node.name)) {
      final factor = _linearColor(color);
      final mesh = node.mesh;
      if (mesh != null) {
        for (final primitive in mesh.primitives) {
          primitive.material = s.PhysicallyBasedMaterial()
            ..baseColorFactor = factor
            ..roughnessFactor = .55;
        }
      }
    }
    for (final child in node.children) {
      _paintHelmet(child, color);
    }
  }

  // The glTF root is a Z mirror. Reading it back as rotation and scale turns
  // that mirror into a half turn, so the nose points at the camera.
  void _faceTrack(s.Node mesh, double scale) {
    mesh.localTransform = v.Matrix4.diagonal3Values(scale, scale, scale);
  }

  v.Vector4 _linearColor(int color) {
    final channels = Color(color);
    double linear(double channel) => channel <= .04045
        ? channel / 12.92
        : math.pow((channel + .055) / 1.055, 2.4).toDouble();
    return v.Vector4(
      linear(channels.r),
      linear(channels.g),
      linear(channels.b),
      1,
    );
  }

  _Kart _characterKart(s.Node root, s.Node body, int color) {
    final mesh = _newKart!.clone();
    _faceTrack(mesh, 2.06 * .98 / 1.428);
    _paintCharacter(mesh, color);
    _plainKart(mesh);
    body.add(mesh);
    final wheels = [
      for (final name in [
        'wheel-front-left',
        'wheel-front-right',
        'wheel-back-left',
        'wheel-back-right',
      ])
        mesh.getChildByName(name)!,
    ];
    final flames = [
      for (final side in [-.2, .2])
        _flame(mesh, side, at: v.Vector3(side * .7, .22, -.58)),
    ];
    final smoke = <_TireSmoke>[
      for (final (index, side) in [-1.0, 1.0].indexed)
        _smoke(
          mesh,
          side,
          at: wheels[index + 2].position + v.Vector3(0, .04, 0),
        ),
    ];
    return _Kart(root, body, wheels, flames, smoke, style: 2);
  }

  Future<void> _loadOobiAtlas() async {
    final data = await rootBundle.load('assets/karts/kart-oobi.glb');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final view = ByteData.sublistView(bytes);
    final jsonLen = view.getUint32(12, Endian.little);
    final json =
        jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLen)))
            as Map<String, dynamic>;
    final bin = 20 + jsonLen + 8;
    final image = (json['images'] as List).first as Map<String, dynamic>;
    final bufferView =
        (json['bufferViews'] as List)[image['bufferView'] as int]
            as Map<String, dynamic>;
    final start = bin + (bufferView['byteOffset'] as int? ?? 0);
    final png = bytes.sublist(start, start + (bufferView['byteLength'] as int));
    final frame = await (await ui.instantiateImageCodec(png)).getNextFrame();
    final raw = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    _oobiSize = frame.image.width;
    _oobiPixels = raw!.buffer.asUint8List();
    frame.image.dispose();
  }

  s.Texture2D _oobiTint(int color) => _oobiTints.putIfAbsent(color, () {
    final out = Uint8List.fromList(_oobiPixels!);
    final red = (color >> 16) & 255;
    final green = (color >> 8) & 255;
    final blue = color & 255;
    const orange = 0.299 * 255 + 0.587 * 126 + 0.114 * 68;
    for (var i = 0; i < out.length; i += 4) {
      final r = out[i], g = out[i + 1], b = out[i + 2];
      final maxChannel = math.max(r, math.max(g, b));
      final minChannel = math.min(r, math.min(g, b));
      if (maxChannel < 40 || maxChannel == minChannel) continue;
      if ((maxChannel - minChannel) / maxChannel < .28) continue;
      final scale =
          (0.299 * r + 0.587 * g + 0.114 * b) / orange;
      out[i] = (red * scale).round().clamp(0, 255);
      out[i + 1] = (green * scale).round().clamp(0, 255);
      out[i + 2] = (blue * scale).round().clamp(0, 255);
    }
    return s.Texture2D.fromPixels(out, _oobiSize, _oobiSize);
  });

  void _paintCharacter(s.Node node, int color) {
    final mesh = node.mesh;
    if (mesh != null && _oobiPixels != null) {
      final tint = _oobiTint(color);
      for (final primitive in mesh.primitives) {
        primitive.material = s.PhysicallyBasedMaterial(baseColorTexture: tint)
          ..metallicFactor = 0
          ..roughnessFactor = .85
          ..doubleSided = true;
      }
    }
    for (final child in node.children) {
      _paintCharacter(child, color);
    }
  }

  void _plainKart(s.Node node) {
    node.shadowCastingMode = s.ShadowCastingMode.off;
    node.frustumCulled = false;
    for (final child in node.children) {
      _plainKart(child);
    }
  }

  s.Node _flame(s.Node body, double side, {v.Vector3? at}) {
    final anchor = s.Node()
      ..position = at ?? v.Vector3(side, .42, -1.34)
      ..visible = false
      ..frustumCulled = false;
    body.add(anchor);
    void tongue(double height, double nozzle, double tip, int color) {
      final node = _mesh(
        s.CylinderGeometry(
          topRadius: tip,
          bottomRadius: nozzle,
          height: height,
          radialSegments: 8,
        ),
        color,
        0,
        0,
        -height / 2,
        parent: anchor,
      );
      node.rotation = v.Quaternion.axisAngle(v.Vector3(1, 0, 0), -math.pi / 2);
    }

    tongue(1.45, .09, .032, 0xFFFFD98A);
    tongue(.95, .046, .016, 0xFFF4FBFF);
    return anchor;
  }

  _TireSmoke _smoke(s.Node body, double side, {v.Vector3? at}) {
    final texture = _smokeTexture ??= s.Texture2D.fromPixels(
      _smokeSprite(),
      48,
      48,
      content: s.TextureContent.data,
      sampling: const s.TextureSampling(mipmaps: false),
    );
    final material = _smokeMaterial ??= s.SpriteMaterial(colorTexture: texture)
      ..blendMode = s.SpriteBlendMode.alpha
      ..softDepthFade = .08;
    final trailShape = _TireSmokeShape();
    final trail = _puffs(
      shape: trailShape,
      material: material,
      side: side,
      life: const s.UniformFloat(.5, .85),
      size: const s.UniformFloat(.24, .42),
      speed: const s.UniformFloat(.25, .6),
      cap: 72,
    );
    final trailNode = s.Node()..frustumCulled = false;
    trailNode.addComponent(trail);
    _scene!.add(trailNode);
    final keptTrail = trailNode;
    final hug = _puffs(
      shape: _TireSmokeShape()..spread = .24,
      material: material,
      side: side + 3,
      life: const s.UniformFloat(.28, .48),
      size: const s.UniformFloat(.16, .28),
      speed: const s.UniformFloat(.18, .4),
      cap: 28,
    );
    final hugNode = s.Node()
      ..position = at ?? v.Vector3(side * .71, .22, -.72)
      ..frustumCulled = false;
    hugNode.addComponent(hug);
    body.add(hugNode);
    return _TireSmoke(trail, hug, trailShape, side, keptTrail);
  }

  void _dropKarts() {
    for (final kart in _karts.values) {
      for (final tire in kart.smoke) {
        tire.trailNode.parent?.remove(tire.trailNode);
      }
      kart.root.parent?.remove(kart.root);
    }
    _karts.clear();
  }

  s.ParticleEmitterComponent _puffs({
    required _TireSmokeShape shape,
    required s.SpriteMaterial material,
    required double side,
    required s.FloatDistribution life,
    required s.FloatDistribution size,
    required s.FloatDistribution speed,
    int cap = 64,
  }) {
    return s.ParticleEmitterComponent(
      system: s.ParticleSystem(
        maxParticles: cap,
        shape: shape,
        spawner: s.Spawner(),
        modules: [
          s.SizeOverLifeModule(
            s.CurveFloat(
              s.ParticleCurve([
                const s.ParticleKeyframe(0, .75),
                const s.ParticleKeyframe(.25, 1.05),
                const s.ParticleKeyframe(1, 1.45),
              ]),
            ),
          ),
          s.ColorOverLifeModule(
            s.GradientColor(
              s.ColorGradient([
                s.ColorStop(0, v.Vector4(.92, .91, .88, 0)),
                s.ColorStop(.12, v.Vector4(.96, .95, .92, .48)),
                s.ColorStop(.55, v.Vector4(.9, .89, .86, .16)),
                s.ColorStop(1, v.Vector4(.82, .81, .78, 0)),
              ]),
            ),
          ),
          s.LinearDragModule(2.4),
          s.TurbulenceModule(strength: .25, frequency: 1.4, seed: side.round()),
          const s.RotationModule(),
        ],
        lifetime: life,
        startSpeed: speed,
        startSize: size,
        startRotation: s.UniformFloat(0, math.pi * 2),
        gravity: v.Vector3(0, .16, 0),
        seed: side.round() + 11,
      ),
      material: material,
    )..aspectRatio = 1.3;
  }

  void _tick(Duration elapsed, double dt) {
    if (dt > 0) {
      _presented = true;
      widget.onAdvance?.call(dt);
    }
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
      final speed = car.speed.isFinite ? car.speed : 0.0;
      final steer = car.steering.isFinite ? car.steering : 0.0;
      final step = dt.isFinite ? dt.clamp(0.0, .05) : 0.0;
      final blend = 1 - math.exp(-step * 6);
      final driftBlend = 1 - math.exp(-step * 2.4);
      final rate = step > 0 ? (speed - kart.lastSpeed) / step : 0.0;
      final pitchTarget = !rate.isFinite
          ? 0.0
          : rate > 140
          ? -.045
          : rate < -220
          ? .035
          : 0.0;
      if (!kart.pitch.isFinite) kart.pitch = 0;
      if (!kart.drift.isFinite) kart.drift = 0;
      if (!kart.lean.isFinite) kart.lean = 0;
      if (!kart.puff.isFinite) kart.puff = 0;
      kart.pitch += (pitchTarget - kart.pitch) * blend;
      final driftTarget = speed.abs() > 70
          ? ((steer.abs() - .2) / .7).clamp(0.0, 1.0)
          : 0.0;
      final leanTarget = driftTarget * steer.sign;
      final release = leanTarget.abs() < kart.lean.abs();
      final leanBlend = 1 - math.exp(-step * (release ? 1.15 : 2.4));
      kart.lean = (kart.lean + (leanTarget - kart.lean) * leanBlend).clamp(
        -1.0,
        1.0,
      );
      kart.drift = kart.lean.abs();
      kart.puff = (kart.puff + (kart.drift - kart.puff) * driftBlend).clamp(
        0.0,
        1.0,
      );
      kart.lastSpeed = speed;
      final motion = (speed.abs() / 405).clamp(0.0, 1.0);
      final heading = car.heading.isFinite ? car.heading : 0.0;
      kart.root.position = position;
      kart.root.rotation = v.Quaternion.axisAngle(
        v.Vector3(0, 1, 0),
        math.pi / 2 - heading,
      );
      final slide = kart.lean * -.16;
      final attitude =
          v.Quaternion.axisAngle(v.Vector3(0, 1, 0), kart.lean * .22) *
          v.Quaternion.axisAngle(
            v.Vector3(0, 0, 1),
            -.04 * steer * (speed / 405),
          ) *
          v.Quaternion.axisAngle(v.Vector3(1, 0, 0), kart.pitch);
      kart.body.rotation = attitude;
      const axle = .3;
      final swung = attitude.rotated(v.Vector3(0, -axle, 0));
      final bounce =
          (.5 + .5 * math.sin(seconds * 18 + car.driver.slot)) * .008 * motion;
      kart.body.position = kart.style == 2
          ? v.Vector3(slide + swung.x, .045 + axle + swung.y + bounce, swung.z)
          : v.Vector3(slide, bounce, 0);
      kart.spin =
          (kart.spin + step * (speed / 20) / (.33 * .98)) % (math.pi * 2);
      for (final (index, wheel) in kart.wheels.indexed) {
        final front = index < 2;
        if (kart.style == 1) {
          wheel.rotation =
              v.Quaternion.axisAngle(
                v.Vector3(0, 1, 0),
                front ? steer * .3 : 0,
              ) *
              v.Quaternion.axisAngle(v.Vector3(0, 0, 1), math.pi / 2) *
              v.Quaternion.axisAngle(v.Vector3(0, 1, 0), kart.spin);
        } else {
          final steerAngle = front ? steer * .55 : kart.lean * .2;
          final camber = (front ? .05 : .12) * -kart.lean;
          wheel.rotation =
              v.Quaternion.axisAngle(v.Vector3(0, 1, 0), steerAngle) *
              v.Quaternion.axisAngle(v.Vector3(0, 0, 1), camber) *
              v.Quaternion.axisAngle(v.Vector3(1, 0, 0), -kart.spin);
        }
      }
      final forward = kart.root.rotation.rotated(v.Vector3(0, 0, 1));
      final right = kart.root.rotation.rotated(v.Vector3(1, 0, 0));
      final pulling = !rate.isFinite || rate < 70
          ? 0.0
          : ((rate - 70) / 160).clamp(0.0, 1.0) *
                (1 - (speed.abs() / 380).clamp(0.0, .8));
      final launch = math.max(pulling, car.boosting ? .9 : 0.0);
      final slip = kart.drift < .12
          ? 0.0
          : ((kart.drift - .12) / .88).clamp(0.0, 1.0);
      for (final (index, tire) in kart.smoke.indexed) {
        final at = kart.wheels[index + 2].globalTransform.getTranslation();
        final outside = tire.side * -steer.sign;
        final slide = -steer.sign * slip;
        tire.shape.contact.setValues(
          at.x + right.x * slide * .55,
          height + .06,
          at.z + right.z * slide * .55,
        );
        final here = (launch + slip * (outside > 0 ? 1.2 : .45)).clamp(
          0.0,
          1.3,
        );
        final thrown =
            forward * -.4 + v.Vector3(0, .5, 0) + right * (slide * 2.2);
        final length = thrown.length;
        if (length > 1e-4) {
          tire.shape.direction.setFrom(thrown / length);
        }
        final smoking = here > .08;
        tire.trail.system.spawner.rate = smoking ? 14 + here * 36 : 0;
        tire.hug.system.spawner.rate = smoking ? 6 + here * 16 : 0;
      }
      for (final (index, flame) in kart.flames.indexed) {
        flame.visible = car.boosting;
        if (!car.boosting) continue;
        flame.scale = kart.style != 2
            ? v.Vector3(.8, .8, 2.2 + math.sin(seconds * 55) * .7)
            : v.Vector3(1, 1, .78 + .22 * math.sin(seconds * 46 + index * 1.4));
      }
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
      final approachRaw = widget.approach;
      final approach = approachRaw.isFinite ? approachRaw.clamp(0.0, 1.0) : 1.0;
      final eye = v.Vector3(
        car.x / 20 - math.cos(car.heading) * (6 + (1 - approach) * 16),
        height + 2.8 + (1 - approach) * 9,
        car.y / 20 - math.sin(car.heading) * (6 + (1 - approach) * 16),
      );
      if (!_finite3(eye) || !_finite3(target)) continue;
      final camera = _playerCameras.putIfAbsent(
        car.driver.id,
        () => s.PerspectiveCamera(
          position: eye.clone(),
          target: target.clone(),
          fovRadiansY: 1.0,
          fovNear: .2,
        ),
      );
      final follow =
          1 - math.exp(-(dt.isFinite ? dt.clamp(0.0, .05) : 0.0) * 5);
      if (!camera.position.x.isFinite ||
          !camera.target.x.isFinite ||
          !camera.fovRadiansY.isFinite) {
        camera.position.setFrom(eye);
        camera.target.setFrom(target);
        camera.fovRadiansY = 1;
      } else {
        camera.position += (eye - camera.position) * follow;
        camera.target += (target - camera.target) * follow;
        camera.fovRadiansY +=
            (1.0 +
                .12 * (car.speed.abs() / 405).clamp(0, 1) +
                (car.boosting ? .06 : 0) -
                camera.fovRadiansY) *
            follow;
      }
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
    if (_scene == null) return const _LoadingTrack();
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.race == null ? 24 : 0),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF97D9E6))),
            Positioned.fill(
              child: s.SceneView(
                _scene!,
                viewsBuilder: _views,
                onTick: _tick,
                maxFrameRate: widget.race == null ? 30 : 60,
                warmUp: true,
                pixelRatio: _pixelRatio(context, constraints.biggest),
                loadingBuilder: (context, _) => const _LoadingTrack(),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(child: CustomPaint(painter: _hud)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _pixelRatio(BuildContext context, Size size) {
    if (!Platform.isAndroid) return 1;
    final longSide = math.max(size.width, size.height);
    if (longSide <= 0 || !longSide.isFinite) return 1;
    final native = View.of(context).devicePixelRatio;
    return math.min(native, 1280 / longSide);
  }
}

bool _finite3(v.Vector3 value) =>
    value.x.isFinite && value.y.isFinite && value.z.isFinite;

class _Kart {
  _Kart(
    this.root,
    this.body,
    this.wheels,
    this.flames,
    this.smoke, {
    required this.style,
  });
  final s.Node root, body;
  final List<s.Node> wheels, flames;
  final List<_TireSmoke> smoke;
  final int style;
  double spin = 0, pitch = 0, drift = 0, lean = 0, puff = 0, lastSpeed = 0;
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

String? _standingGap(Race race, Car car, List<Car> standings) {
  final place = standings.indexOf(car);
  if (place <= 0) return null;
  String gapTo(Car ahead) {
    final laps = (ahead.progress - car.progress) / (math.pi * 2);
    final seconds = laps * race.circuit.length / math.max(car.speed.abs(), 50);
    if (!seconds.isFinite || seconds <= 0) return '+0.00';
    return '+${seconds.toStringAsFixed(seconds >= 10 ? 1 : 2)}';
  }

  final ahead = standings[place - 1];
  final leader = gapTo(standings.first);
  if (place == 1) return leader;
  return 'L $leader  ${gapTo(ahead)}';
}

void _minimap(Canvas canvas, Size size, Race race) {
  final order = race.standings;
  final count = order.length;
  final fit = count <= 1
      ? 1.0
      : count == 2
      ? .72
      : count <= 4
      ? .58
      : .46;
  final mapWidth = 150.0 * fit, mapHeight = 96.0 * fit;
  final card = Size(
    mapWidth + 100 * fit,
    math.max(mapHeight, count * 14.0 * fit) + 16,
  );
  const margin = 16.0;
  final origin = Offset(
    size.width - card.width - margin,
    count <= 1 ? size.height - card.height - margin : margin,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      (origin & card).shift(const Offset(0, 4)),
      const Radius.circular(12),
    ),
    Paint()..color = const Color(0x66000000),
  );
  final bounds = origin & card;
  canvas.drawRRect(
    RRect.fromRectAndRadius(bounds, const Radius.circular(10)),
    Paint()..color = const Color(0xF0111918),
  );
  final map = Rect.fromLTWH(origin.dx + 8, origin.dy + 8, mapWidth, mapHeight);
  final circuit = race.circuit;
  final spanX = math.max(1.0, circuit.maxX - circuit.minX);
  final spanY = math.max(1.0, circuit.maxY - circuit.minY);
  final scale = math.min((map.width - 12) / spanX, (map.height - 12) / spanY);
  final center = Offset(
    (circuit.minX + circuit.maxX) / 2,
    (circuit.minY + circuit.maxY) / 2,
  );
  Offset point(double x, double y) =>
      map.center + Offset((x - center.dx) * scale, (center.dy - y) * scale);
  final path = Path();
  for (var i = 0; i < circuit.points.length; i++) {
    final spot = point(circuit.points[i].x, circuit.points[i].y);
    if (i == 0) {
      path.moveTo(spot.dx, spot.dy);
    } else {
      path.lineTo(spot.dx, spot.dy);
    }
  }
  canvas.drawPath(
    path..close(),
    Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round,
  );
  final label = TextPainter(textDirection: TextDirection.ltr);
  for (var i = 0; i < order.length; i++) {
    final car = order[i];
    final color = Color(car.driver.color);
    final spot = point(car.x, car.y);
    canvas.drawCircle(spot, 5, Paint()..color = color);
    label.text = TextSpan(
      text: '${i + 1}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w800,
      ),
    );
    label.layout();
    label.paint(canvas, spot + const Offset(6, -6));
    label.text = TextSpan(
      text: '${i + 1} ${car.driver.name}',
      style: TextStyle(
        color: color,
        fontSize: 11 * fit,
        fontWeight: FontWeight.w800,
      ),
    );
    label.layout(maxWidth: 92 * fit);
    label.paint(canvas, Offset(map.right + 8, origin.dy + 8 + i * 14 * fit));
  }
  label.dispose();
}

class _HudPanel {
  double width = 168;
  double height = 72;
}

class _PlayerHud extends CustomPainter {
  _PlayerHud(
    this.race,
    ChangeNotifier repaint, {
    required this.tvMode,
    required this.presented,
  }) : super(repaint: repaint);
  final Race? Function() race;
  final bool Function() tvMode;
  final bool Function() presented;
  final _textPainters = <TextPainter>[];
  final _panels = <int, _HudPanel>{};
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
    if (current == null || !presented()) return;
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
      final scale = (math.min(rect.width, rect.height) / (tvMode() ? 360 : 320))
          .clamp(.55, 1.0);
      final insetX = math.max(18.0, rect.width * .035);
      final insetY = math.max(16.0, rect.height * .04);
      canvas.save();
      canvas.translate(rect.left + insetX, rect.top + insetY);
      canvas.scale(scale);
      final color = Color.lerp(Color(car.driver.color), Colors.white, .2)!;
      final place = standings.indexOf(car) + 1;
      final title = car.retired
          ? 'SAIU'
          : car.finishedAt != null
          ? 'CHEGOU'
          : car.driver.name;
      final placeText = car.retired ? '—' : '$placeº';
      final timeText = car.finishedAt == null
          ? formatRaceTime(car.lapTime(current.elapsed))
          : formatRaceTime(car.finishedAt!);
      final lapText =
          '${math.min(car.laps + 1, current.totalLaps)}/${current.totalLaps}';
      final gap = _standingGap(current, car, standings);
      final best = car.bestLap == null
          ? null
          : 'melhor ${formatRaceTime(car.bestLap!)}';
      final racing = car.finishedAt == null && !car.retired;
      final measure = TextPainter(textDirection: TextDirection.ltr);
      double widthOf(String value, double fontSize) {
        measure.text = TextSpan(
          text: value,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
        );
        measure.layout();
        return measure.width;
      }

      final trackName = current.circuit.name;
      final placeWidth = widthOf(placeText, 28);
      final nameWidth = widthOf(title, 15);
      final trackWidth = widthOf(trackName, 13);
      final timeWidth = widthOf(timeText, 14);
      final lapWidth = widthOf(lapText, 14);
      final gapWidth = gap == null ? 0.0 : widthOf(gap, 13);
      final bestWidth = best == null ? 0.0 : widthOf(best, 13);
      measure.dispose();
      final contentWidth = [
        placeWidth + 10 + nameWidth,
        trackWidth,
        timeWidth + 28 + lapWidth,
        gapWidth,
        bestWidth,
        148.0,
      ].reduce(math.max);
      var contentHeight = 36.0 + 8 + 16 + 20;
      if (gap != null) contentHeight += 8 + 14;
      if (best != null) contentHeight += 8 + 14;
      if (racing) contentHeight += 12 + 10;
      final panel = _panels.putIfAbsent(car.driver.slot, _HudPanel.new);
      panel.width = contentWidth + 28;
      panel.height = contentHeight + 20;
      final card = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, panel.width, panel.height),
        const Radius.circular(14),
      );
      canvas.drawRRect(
        card.shift(const Offset(0, 4)),
        Paint()..color = const Color(0x73000000),
      );
      canvas.drawRRect(card, Paint()..color = ink);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, 5, panel.height),
          const Radius.circular(3),
        ),
        Paint()..color = color,
      );
      _text(canvas, placeText, const Offset(16, 8), 32, color);
      _text(canvas, title, Offset(22 + placeWidth, 20), 16, Colors.white);
      var line = 46.0;
      _text(canvas, trackName, Offset(16, line), 13, lime);
      line += 20;
      _text(canvas, timeText, Offset(16, line), 15, Colors.white);
      _text(
        canvas,
        lapText,
        Offset(panel.width - lapWidth - 16, line),
        15,
        lime,
      );
      line += 24;
      if (gap != null) {
        _text(canvas, gap, Offset(16, line), 13, Colors.white);
        line += 22;
      }
      if (best != null) {
        _text(canvas, best, Offset(16, line), 13, lime);
        line += 22;
      }
      if (racing) {
        final bar = Rect.fromLTWH(16, line, panel.width - 32, 10);
        canvas.drawRRect(
          RRect.fromRectAndRadius(bar, const Radius.circular(5)),
          Paint()..color = const Color(0x33FFFFFF),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              bar.left,
              bar.top,
              bar.width * car.boostCharge,
              bar.height,
            ),
            const Radius.circular(5),
          ),
          Paint()..color = car.boosting ? const Color(0xFFFFD061) : color,
        );
      }
      canvas.restore();
      final wrongWay =
          racing &&
          car.speed.abs() > 30 &&
          () {
            final track = current.circuit.heading(car.trackAngle);
            final delta = math.atan2(
              math.sin(car.heading - track),
              math.cos(car.heading - track),
            );
            return delta.abs() > math.pi / 2;
          }();
      if (wrongWay) {
        const warning = 'CONTRA MÃO';
        final warningSize = (rect.height * .075).clamp(22.0, 42.0);
        final warningPainter = TextPainter(
          text: TextSpan(
            text: warning,
            style: TextStyle(
              fontSize: warningSize,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final plate = Rect.fromCenter(
          center: rect.center,
          width: warningPainter.width + 36,
          height: warningPainter.height + 18,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            plate.shift(const Offset(0, 3)),
            const Radius.circular(8),
          ),
          Paint()..color = const Color(0x66000000),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(plate, const Radius.circular(8)),
          Paint()..color = const Color(0xFFE23B4A),
        );
        warningPainter.paint(
          canvas,
          plate.center -
              Offset(warningPainter.width / 2, warningPainter.height / 2),
        );
        warningPainter.dispose();
      }
      canvas.restore();
    }
    _minimap(canvas, size, current);
  }

  @override
  bool shouldRepaint(_PlayerHud oldDelegate) => true;
}

class _LoadingTrack extends StatefulWidget {
  const _LoadingTrack();

  @override
  State<_LoadingTrack> createState() => _LoadingTrackState();
}

class _LoadingTrackState extends State<_LoadingTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ink,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VoltaMark(height: 48),
            const SizedBox(height: 28),
            const Text(
              'Carregando a pista',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 220,
              height: 8,
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) {
                  final travel = _motion.value;
                  return CustomPaint(painter: _LoadBar(travel));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadBar extends CustomPainter {
  _LoadBar(this.travel);
  final double travel;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0xFF2A332C));
    final width = size.width * .38;
    final left = (size.width + width) * travel - width;
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, width, size.height),
        const Radius.circular(4),
      ),
      Paint()..color = lime,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LoadBar oldDelegate) => oldDelegate.travel != travel;
}

/// Soft radial puff. The edge is clear so the billboard quad never shows.
Uint8List _smokeSprite() {
  const n = 48;
  final pixels = Uint8List(n * n * 4);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final u = (x + .5) / n * 2 - 1;
      final v = (y + .5) / n * 2 - 1;
      final disc = (1 - math.sqrt(u * u + v * v) / .92).clamp(0.0, 1.0);
      final lobe =
          (1 - math.sqrt((u - .16) * (u - .16) + (v + .08) * (v + .08)) / .55)
              .clamp(0.0, 1.0);
      final alpha = (disc * disc * .82 + lobe * lobe * .28).clamp(0.0, 1.0);
      final i = (y * n + x) * 4;
      pixels[i] = 255;
      pixels[i + 1] = 250;
      pixels[i + 2] = 242;
      pixels[i + 3] = (alpha * 255).round();
    }
  }
  return pixels;
}

class _TireSmoke {
  _TireSmoke(this.trail, this.hug, this.shape, this.side, this.trailNode);
  final s.ParticleEmitterComponent trail, hug;
  final _TireSmokeShape shape;
  final double side;
  final s.Node trailNode;
}

/// Drops a puff in world space, at the tire, thrown back and up.
class _TireSmokeShape extends s.EmitterShape {
  final contact = v.Vector3.zero();
  final direction = v.Vector3(0, .9, -.35)..normalize();
  double spread = .1;

  @override
  void sample(s.ParticleStorage storage, int index) {
    final disc = spread * math.sqrt(storage.randomFor(index, 20));
    final angle = storage.randomFor(index, 21) * math.pi * 2;
    storage.posX[index] = contact.x + disc * math.cos(angle);
    storage.posY[index] = contact.y;
    storage.posZ[index] = contact.z + disc * math.sin(angle);
    storage.velX[index] = direction.x;
    storage.velY[index] = direction.y;
    storage.velZ[index] = direction.z;
  }
}
