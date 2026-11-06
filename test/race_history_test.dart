import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volta/game/race.dart';
import 'package:volta/room/race_history.dart';
import 'package:volta/room/session.dart';

void main() {
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
