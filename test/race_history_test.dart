import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volta/game/race.dart';
import 'package:volta/room/race_history.dart';
import 'package:volta/room/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('home and keyboard practice reuse the same connected room', () async {
    final directory = await Directory.systemTemp.createTemp('volta-room');
    addTearDown(() => directory.delete(recursive: true));
    final session = Session(
      history: RaceHistory(file: File('${directory.path}/races.json')),
    );
    addTearDown(() async {
      await session.leave();
      session.dispose();
    });
    await session.open();
    final code = session.state.code;
    expect(code, isNotNull);
    final address = session.state.addresses.first;
    session.selectedAddress = address;
    final url = Uri.parse(address);
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${url.port}/room${url.path}',
    ).timeout(const Duration(seconds: 5));
    addTearDown(socket.close);
    final welcome = socket
        .asBroadcastStream()
        .map((message) => jsonDecode(message as String) as Map<String, dynamic>)
        .firstWhere((message) => message['type'] == 'welcome');
    socket.add(jsonEncode({'type': 'join', 'name': 'Ana'}));
    final token = (await welcome.timeout(const Duration(seconds: 5)))['token'];

    session.home();
    expect(session.onHome, isTrue);
    session.local();
    session.home();
    await session.open();

    expect(session.onHome, isFalse);
    expect(session.state.code, code);
    expect(session.selectedAddress, address);
    expect(session.state.room!.players.single.id, token);
    expect(session.state.room!.players.single.connected, isTrue);
  });

  test('session saves a finished keyboard race once', () async {
    final directory = await Directory.systemTemp.createTemp('volta-session');
    addTearDown(() => directory.delete(recursive: true));
    final session = Session(
      history: RaceHistory(file: File('${directory.path}/races.json')),
    );
    addTearDown(session.dispose);
    session.local();
    final race = Race([
      const Driver('1', 'Ana', 0),
      const Driver('2', 'Bia', 1),
    ]);
    race.cars[0].finishedAt = 50;
    race.cars[1].finishedAt = 60;
    await Future.wait([session.finish(race), session.finish(race)]);
    expect(session.history.races.length, 1);
    expect(session.historyError, isNull);
    final reloaded = RaceHistory(file: session.history.file);
    await reloaded.load();
    expect(reloaded.races.length, 1);
  });
  test(
    'results persist across restarts and count only completed winners',
    () async {
      final directory = await Directory.systemTemp.createTemp('volta-history');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/data/races.json');
      final history = RaceHistory(file: file);
      await history.load();
      final race = Race([
        const Driver('1', 'Ana', 0),
        const Driver('2', 'Bia', 1),
      ]);
      await history.record(race);
      expect(history.races, isEmpty);
      race.cars[0].finishedAt = 60;
      race.cars[1].retired = true;
      await history.record(race);
      final next = Race([
        const Driver('3', 'ana', 0),
        const Driver('4', 'Bia', 1),
      ]);
      next.cars[0].retired = true;
      next.cars[1].retired = true;
      await history.record(next);
      final restored = RaceHistory(file: file);
      await restored.load();
      expect(restored.races.length, 2);
      final leaders = restored.snapshot['leaders'] as List;
      expect(leaders.first['name'], 'Ana');
      expect(leaders.first['wins'], 1);
      expect(leaders.first['races'], 2);
      expect(leaders.last['wins'], 0);
      expect(restored.races.first['results'][0]['time'], 60);
      expect(restored.races.first['results'][1]['retired'], true);
    },
  );
}
