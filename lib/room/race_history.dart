import 'dart:convert';
import 'dart:io';

import '../game/race.dart';

class RaceHistory {
  RaceHistory({File? file})
    : file =
          file ??
          File(
            '${Platform.environment['HOME']!}/Library/Application Support/volta/races.json',
          );

  final File file;
  final races = <Map<String, dynamic>>[];
  Future<void> _pending = Future.value();

  Future<void> load() async {
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    races.addAll((data['races'] as List).cast<Map<String, dynamic>>());
  }

  Map<String, Object> get snapshot {
    final totals = <String, Map<String, Object>>{};
    for (final race in races) {
      for (final result in race['results'] as List) {
        final name = result['name'] as String;
        final key = name.toLowerCase();
        final total = totals.putIfAbsent(
          key,
          () => {'name': name, 'races': 0, 'wins': 0},
        );
        total['races'] = (total['races'] as int) + 1;
        if (result['rank'] == 1 && result['time'] != null) {
          total['wins'] = (total['wins'] as int) + 1;
        }
      }
    }
    final leaders = totals.values.toList()
      ..sort((a, b) {
        final wins = (b['wins'] as int).compareTo(a['wins'] as int);
        return wins != 0
            ? wins
            : (a['name'] as String).compareTo(b['name'] as String);
      });
    return {'races': races.reversed.toList(), 'leaders': leaders};
  }

  Future<void> record(Race race) {
    if (!race.finished) return Future.value();
    final results = race.standings;
    races.add({
      'date': DateTime.now().toUtc().toIso8601String(),
      'circuit': race.circuit.name,
      'lapCount': race.totalLaps,
      'turbo': race.turbo,
      'mirrored': race.mirrored,
      'reversed': race.reversed,
      'timeTrial': race.timeTrial,
      'results': [
        for (var i = 0; i < results.length; i++)
          {
            'name': results[i].driver.name.trim(),
            'rank': i + 1,
            'time': results[i].finishedAt,
            'retired': results[i].retired,
            'laps': List<double>.of(results[i].lapTimes),
            'bestLap': results[i].bestLap,
          },
      ],
    });
    final contents = jsonEncode({'version': 1, 'races': races});
    final write = _pending.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(file.path);
    });
    _pending = write.catchError((Object _) {});
    return write;
  }

  ({String name, double time})? bestOn(String circuit) {
    String? name;
    double? time;
    for (final race in races) {
      if (race['timeTrial'] != true || race['circuit'] != circuit) continue;
      for (final result in race['results'] as List) {
        final lap = result['bestLap'];
        if (lap is! num) continue;
        if (time != null && lap >= time) continue;
        time = lap.toDouble();
        name = result['name'] as String;
      }
    }
    if (name == null || time == null) return null;
    return (name: name, time: time);
  }
}
