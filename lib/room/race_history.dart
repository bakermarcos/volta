import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../game/race.dart';
import 'browser_platform.dart';

class RaceHistory {
  RaceHistory({File? file}) : _providedFile = file;

  final File? _providedFile;

  static File _defaultFile() {
    final env = Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.systemTemp.path;
    final dataRoot = switch (Platform.operatingSystem) {
      'windows' => env['LOCALAPPDATA'] ?? '$home/AppData/Local',
      'linux' =>
        env['XDG_DATA_HOME']?.startsWith('/') == true
            ? env['XDG_DATA_HOME']!
            : '$home/.local/share',
      _ => '$home/Library/Application Support',
    };
    return File('$dataRoot/volta/races.json');
  }

  late final File file = _providedFile ?? _defaultFile();
  final races = <Map<String, dynamic>>[];
  Future<void> _pending = Future.value();

  Future<void> load() async {
    final contents = kIsWeb
        ? readBrowserHistory()
        : await file.exists()
        ? await file.readAsString()
        : null;
    if (contents == null) return;
    final data = jsonDecode(contents) as Map<String, dynamic>;
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
      if (kIsWeb) {
        writeBrowserHistory(contents);
        return;
      }
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
