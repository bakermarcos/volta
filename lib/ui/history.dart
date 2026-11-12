import 'package:flutter/material.dart';

import '../room/session.dart';
import '../game/race.dart';
import 'track.dart';

Future<void> showRaceHistory(BuildContext context) async {
  final session = SessionScope.read(context);
  await session.ready;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) {
      final data = session.history.snapshot;
      final size = MediaQuery.sizeOf(context);
      return Dialog(
        child: SizedBox(
          width: size.width < 640 ? size.width * .92 : 560,
          height: size.height * .86,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Histórico local',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      autofocus: true,
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Text(
                  'Salvo neste aparelho · pilotos agrupados pelo nome',
                  style: TextStyle(color: muted),
                ),
                if (session.historyError != null)
                  Text(
                    session.historyError!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      if (session.history.races.isEmpty)
                        const Text('As corridas concluídas aparecerão aqui.'),
                      for (final leader in data['leaders'] as List)
                        _historyRow(
                          '${leader['name']} · ${leader['wins']} vitórias · ${leader['races']} corridas',
                        ),
                      for (final race in data['races'] as List) ...[
                        const Divider(height: 32),
                        _historyRow(
                          '${race['circuit']}\n${DateTime.parse(race['date'] as String).toLocal().toString().split('.').first}',
                          accent: true,
                        ),
                        for (final result in race['results'] as List)
                          _historyRow(
                            '${result['rank']}. ${result['name']} · ${result['time'] == null ? 'SAIU' : formatRaceTime((result['time'] as num).toDouble())}${(result['laps'] as List?)?.isNotEmpty == true ? '\nVoltas: ${(result['laps'] as List).map((v) => formatRaceTime((v as num).toDouble())).join(' / ')}' : ''}',
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _historyRow(String text, {bool accent = false}) => ListTile(
  contentPadding: EdgeInsets.zero,
  title: Text(
    text,
    style: TextStyle(
      color: accent ? lime : null,
      fontWeight: accent ? FontWeight.bold : null,
    ),
  ),
  onTap: () {},
);
