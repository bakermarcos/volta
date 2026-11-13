import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volta/game/race.dart';
import 'package:volta/room/room_service.dart';

class Peer {
  Peer(this.socket) : messages = StreamIterator(socket);
  final WebSocket socket;
  final StreamIterator<Object?> messages;
  String? token;
  void send(Map<String, Object?> message) => socket.add(jsonEncode(message));
  Future<Map<String, dynamic>> next(String type) async {
    while (await messages.moveNext().timeout(const Duration(seconds: 3))) {
      final message =
          jsonDecode(messages.current as String) as Map<String, dynamic>;
      if (message['type'] == type) return message;
    }
    throw StateError('Socket closed before $type');
  }

  static Future<Peer> join(String url, String name, {String? token}) async {
    final uri = Uri.parse(url);
    final peer = Peer(
      await WebSocket.connect('ws://${uri.authority}/room${uri.path}'),
    );
    peer.send({'type': 'join', 'name': name, 'token': token});
    return peer;
  }
}

void main() {
  test(
    'history endpoint is readable without joining and scoped to the room',
    () async {
      final service = RoomService(
        'controller',
        history: () => {
          'races': [
            {'circuit': 'Brasil'},
          ],
          'leaders': [
            {'name': '<Ana>', 'wins': 2},
          ],
        },
      );
      await service.create(address: InternetAddress.loopbackIPv4);
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(
          Uri.parse('${service.addresses.first}/history'),
        )).close();
        expect(response.statusCode, 200);
        final data = jsonDecode(await utf8.decoder.bind(response).join());
        expect(data['leaders'][0]['wins'], 2);
        final missing = await (await client.getUrl(
          Uri.parse('${service.addresses.first}/other/history'),
        )).close();
        expect(missing.statusCode, 404);
      } finally {
        client.close(force: true);
        await service.dispose();
      }
    },
  );
  late RoomService room;
  final peers = <Peer>[];
  setUp(() async {
    room = RoomService('<html>controle</html>');
    await room.create(address: InternetAddress.loopbackIPv4);
  });
  tearDown(() async {
    for (final peer in peers) {
      await peer.socket.close();
      await peer.messages.cancel();
    }
    peers.clear();
    await room.dispose();
  });
  Future<Peer> join(String name, {String? token}) async {
    final peer = await Peer.join(room.addresses.first, name, token: token);
    peers.add(peer);
    final welcome = await peer.next('welcome');
    peer.token = welcome['token'] as String;
    return peer;
  }

  Future<void> startReady() async {
    final ready = room.changes.firstWhere((s) => s.canStart);
    for (final p in peers.where(
      (p) => p.token != null && p.socket.readyState == WebSocket.open,
    )) {
      p.send({'type': 'ready', 'ready': true});
    }
    await ready.timeout(const Duration(seconds: 3));
    room.start();
    expect(room.status, 'countdown');
    room.advanceCountdown(0);
  }

  test(
    'solo requires readiness and blocks inputs until the countdown ends',
    () async {
      room.start();
      expect(room.status, 'lobby');
      final a = await join('Solo');
      room.start();
      expect(room.status, 'lobby');
      final ready = room.changes.firstWhere((s) => s.canStart);
      a.send({'type': 'ready', 'ready': true});
      await ready;
      room.start();
      expect(room.status, 'countdown');
      expect(room.snapshot.countdown, 3);
      a.send({'type': 'input', 'accelerate': true, 'steer': 0});
      a.send({'type': 'ping'});
      await a.next('pong');
      expect(room.snapshot.inputs, isEmpty);
      room.advanceCountdown(2);
      expect(room.snapshot.countdown, 2);
      room.advanceCountdown(1);
      expect(room.status, 'countdown');
      room.advanceCountdown(0);
      expect(room.status, 'racing');
    },
  );
  test(
    'all connected players must be ready; disconnect cancels countdown',
    () async {
      final a = await join('A');
      final b = await join('B');
      final one = room.changes.firstWhere((s) => s.players.any((p) => p.ready));
      a.send({'type': 'ready', 'ready': true});
      await one;
      room.start();
      expect(room.status, 'lobby');
      final all = room.changes.firstWhere((s) => s.canStart);
      b.send({'type': 'ready', 'ready': true});
      await all;
      room.start();
      final cancelled = room.changes.firstWhere((s) => s.status == 'lobby');
      await b.socket.close();
      await cancelled;
      expect(room.snapshot.countdown, 0);
      expect(room.snapshot.canStart, false);
      expect(room.snapshot.players.every((p) => !p.ready), true);
    },
  );
  test(
    'pause requires two requests by the same player and clears controls',
    () async {
      final a = await join('A');
      final b = await join('B');
      await startReady();
      a.send({'type': 'pause'});
      await a.next('pauseRequest');
      expect(room.paused, false);
      b.send({'type': 'pause'});
      await b.next('pauseRequest');
      expect(room.paused, false);
      final paused = room.changes.firstWhere((s) => s.paused);
      a.send({'type': 'pause'});
      await paused;
      a.send({'type': 'input', 'accelerate': true, 'steer': 0});
      a.send({'type': 'ping'});
      await a.next('pong');
      expect(room.snapshot.inputs, isEmpty);
      room.setPaused(false);
      expect(room.paused, false);
      room.reset();
      expect(room.snapshot.players.every((p) => !p.ready), true);
    },
  );
  test(
    'six unique slots, seventh rejected, no new joins during a race',
    () async {
      for (var i = 0; i < 6; i++) {
        await join('Pilot $i');
      }
      expect(room.snapshot.players.map((p) => p.slot).toSet(), {
        0,
        1,
        2,
        3,
        4,
        5,
      });
      final extra = await Peer.join(room.addresses.first, 'Seventh');
      peers.add(extra);
      expect((await extra.next('error'))['message'], contains('cheia'));
      await startReady();
      final late = await Peer.join(room.addresses.first, 'Late');
      peers.add(late);
      expect((await late.next('error'))['message'], contains('começou'));
    },
  );
  test('six controllers send independent inputs to the same host', () async {
    final drivers = <Peer>[];
    for (var i = 0; i < maxPlayers; i++) {
      drivers.add(await join('Pilot $i'));
    }
    await startReady();
    final all = room.changes.firstWhere((s) => s.inputs.length == maxPlayers);
    for (var i = 0; i < drivers.length; i++) {
      drivers[i].send({
        'type': 'input',
        'accelerate': i.isEven,
        'steer': i % 3 - 1,
      });
    }
    final snapshot = await all.timeout(const Duration(seconds: 3));
    for (var i = 0; i < drivers.length; i++) {
      expect(snapshot.inputs[drivers[i].token]!['accelerate'], i.isEven);
      expect(snapshot.inputs[drivers[i].token]!['steer'], i % 3 - 1);
    }
  });
  test('look sticks to the driver and survives reconnect', () async {
    final a = await join('A');
    final seen = room.changes.firstWhere(
      (s) => s.players.any(
        (p) => p.id == a.token && p.colorIndex == 3 && p.model == 2,
      ),
    );
    a.send({'type': 'look', 'color': 3, 'model': 2});
    await seen.timeout(const Duration(seconds: 3));
    a.send({'type': 'look', 'color': 9, 'model': 4});
    a.send({'type': 'ping'});
    await a.next('pong');
    expect(room.snapshot.players.single.colorIndex, 3);
    expect(room.snapshot.players.single.model, 2);
    final gone = room.changes.firstWhere(
      (s) => s.players.any((p) => p.id == a.token && !p.connected),
    );
    await a.socket.close();
    await gone.timeout(const Duration(seconds: 3));
    final back = await join('A', token: a.token);
    final driver = room.snapshot.players.singleWhere((p) => p.id == back.token);
    expect(driver.connected, isTrue);
    expect(driver.colorIndex, 3);
    expect(driver.model, 2);
    final welcome = await back.next('state');
    expect(welcome['model'], 2);
    expect(welcome['colorIndex'], 3);
  });
  test(
    'socket owns its input; disconnect clears it; token reconnects same car',
    () async {
      final a = await join('A');
      await join('B');
      await startReady();
      final changed = room.changes.firstWhere(
        (s) => s.inputs.containsKey(a.token),
      );
      a.send({
        'type': 'input',
        'accelerate': true,
        'steer': 1,
        'playerId': 'other',
      });
      final snapshot = await changed.timeout(const Duration(seconds: 3));
      expect(snapshot.inputs.keys, [a.token]);
      expect(snapshot.inputs[a.token]!['steer'], 1);
      final disconnected = room.changes.firstWhere(
        (s) => s.players.any((p) => p.id == a.token && !p.connected),
      );
      await a.socket.close();
      await disconnected.timeout(const Duration(seconds: 3));
      expect(room.snapshot.inputs, isEmpty);
      final back = await join('A', token: a.token);
      expect(back.token, a.token);
      expect(room.snapshot.players.length, 2);
      expect(room.snapshot.players.first.connected, isTrue);
    },
  );
  test(
    'analog steering, reverse, boost and own telemetry use local sockets',
    () async {
      final a = await join('A');
      await join('B');
      await startReady();
      final changed = room.changes.firstWhere(
        (s) => s.inputs.containsKey(a.token),
      );
      a.send({
        'type': 'input',
        'accelerate': false,
        'steer': .42,
        'reverse': true,
        'boost': true,
      });
      final snapshot = await changed.timeout(const Duration(seconds: 3));
      expect(snapshot.inputs[a.token]!['steer'], .42);
      expect(snapshot.inputs[a.token]!['reverse'], true);
      expect(snapshot.inputs[a.token]!['boost'], true);
      final race = Race(room.snapshot.players);
      race.cars.first.speed = -50;
      room.telemetry(race);
      final packet = await a.next('telemetry');
      expect(packet['speed'], -50);
      expect(packet['charge'], 1);
      expect(packet.containsKey('players'), false);
    },
  );
  test(
    'host publishes results, rematch and explicit leave frees a slot',
    () async {
      final a = await join('A');
      await join('B');
      await startReady();
      final race = Race(room.snapshot.players);
      race.cars[0].finishedAt = 42;
      race.cars[1].finishedAt = 45;
      room.finish(race);
      expect(room.status, 'finished');
      expect(room.snapshot.results[a.token]!['rank'], 1);
      room.reset();
      expect(room.status, 'lobby');
      expect(room.snapshot.results, isEmpty);
      final left = room.changes.firstWhere((s) => s.players.length == 1);
      a.send({'type': 'leave'});
      await left.timeout(const Duration(seconds: 3));
      await join('C');
      expect(room.snapshot.players.map((p) => p.slot), [0, 1]);
    },
  );
  test('six phones keep the room smooth under a sustained race', () async {
    final drivers = <Peer>[];
    for (var i = 0; i < maxPlayers; i++) {
      drivers.add(await join('Pilot $i'));
    }
    await startReady();
    final clock = Stopwatch()..start();
    for (var tick = 0; tick < 50; tick++) {
      for (final driver in drivers) {
        driver.send({'type': 'input', 'accelerate': true, 'steer': 0});
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    for (var i = 0; i < drivers.length; i++) {
      drivers[i].send({
        'type': 'input',
        'accelerate': true,
        'steer': i.isEven ? .5 : -.5,
        'boost': i.isEven,
      });
    }
    final settled = await room.changes
        .firstWhere(
          (snapshot) => drivers.every(
            (driver) =>
                snapshot.inputs[driver.token]?['steer'] ==
                (drivers.indexOf(driver).isEven ? .5 : -.5),
          ),
        )
        .timeout(const Duration(seconds: 2));
    clock.stop();
    expect(clock.elapsedMilliseconds, lessThan(2000));
    for (final driver in drivers) {
      expect(driver.socket.readyState, WebSocket.open);
      expect(settled.inputs[driver.token]!['accelerate'], true);
    }
    final race = Race(room.snapshot.players);
    final inputs = {
      for (var i = 0; i < race.cars.length; i++)
        race.cars[i].driver.id: ControlInput(
          accelerate: true,
          steer: (i - 2.5) / 5,
        ),
    };
    final simulation = Stopwatch()..start();
    const frames = 600;
    for (var frame = 0; frame < frames; frame++) {
      race.step(1 / 60, inputs);
    }
    simulation.stop();
    expect(simulation.elapsedMicroseconds / frames, lessThan(8000));
    expect(
      race.cars.map((car) => car.speed.abs()).reduce((a, b) => a > b ? a : b),
      greaterThan(100),
    );
  });
}
