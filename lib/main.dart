import 'dart:io';

import 'room/race_history.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'room/session.dart';
import 'ui/host.dart';
import 'ui/track.dart';
import 'ui/history.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    final path = await const MethodChannel('volta/storage')
        .invokeMethod<String>('directory');
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final session = Session(
      history: RaceHistory(file: File('$path/races.json')),
    )..tvMode = true;
    runApp(VoltaApp(session: session));
    return;
  }
  runApp(const VoltaApp());
}

class VoltaApp extends StatefulWidget {
  const VoltaApp({super.key, this.session});
  final Session? session;
  @override
  State<VoltaApp> createState() => _VoltaAppState();
}

class _VoltaAppState extends State<VoltaApp> {
  late final session = widget.session ?? Session();
  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SessionScope(
    session: session,
    child: MaterialApp(
      title: 'Volta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ink,
        colorScheme: ColorScheme.fromSeed(
          seedColor: lime,
          brightness: Brightness.dark,
          primary: lime,
          surface: panel,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 72)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? lime.withValues(alpha: .2)
                  : null,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.focused) ? lime : muted,
                width: states.contains(WidgetState.focused) ? 3 : 1,
              ),
            ),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 64),
            textStyle: const TextStyle(fontSize: 18),
            padding: const EdgeInsets.all(16),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
        ),
        switchTheme: const SwitchThemeData(
          padding: EdgeInsets.symmetric(vertical: 12),
        ),
        listTileTheme: const ListTileThemeData(
          titleTextStyle: TextStyle(fontSize: 20, color: Color(0xFFF1F4EE)),
          subtitleTextStyle: TextStyle(fontSize: 16, color: muted),
          minVerticalPadding: 16,
        ),
        useMaterial3: true,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 72),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            foregroundColor: ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: session.tvMode
            ? (MediaQuery.sizeOf(context).width < 1100 ? 1.1 : 1.3)
            : 1,
        maxScaleFactor: session.tvMode
            ? (MediaQuery.sizeOf(context).width < 1100 ? 1.1 : 1.3)
            : 1.3,
        child: child!,
      ),
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      home: const EntryScreen(),
    ),
  );
}

class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = SessionScope.watch(context);
    final state = session.state;
    if (state.active) return const HostScreen();
    final android = Platform.isAndroid;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: android
                ? const EdgeInsets.symmetric(horizontal: 32, vertical: 16)
                : const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const VoltaMark(height: 64),
                  SizedBox(height: android ? 12 : 16),
                  const Text(
                    'Uma pista. Seus amigos.\nConectem os celulares ao mesmo Wi-Fi.',
                    style: TextStyle(fontSize: 18, color: muted, height: 1.6),
                  ),
                  SizedBox(height: android ? 20 : 40),
                  FilledButton(
                    autofocus: true,
                    onPressed: state.busy ? null : session.open,
                    child: Text(state.busy ? 'Abrindo…' : 'Começar'),
                  ),
                  SizedBox(height: android ? 8 : 12),
                  if (!android)
                    TextButton(
                      onPressed: state.busy ? null : session.local,
                      child: const Text('Treinar com teclado'),
                    ),
                  if (!android)
                    TextButton(
                      onPressed: session.toggleTvMode,
                      child: Text(
                        session.tvMode
                            ? 'Sair do modo TV'
                            : 'Modo TV · tela cheia',
                      ),
                    ),
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () => session.open(timeTrial: true),
                    child: const Text('Tempo na pista'),
                  ),
                  TextButton(
                    onPressed: () => showRaceHistory(context),
                    child: const Text('Histórico de corridas'),
                  ),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(
                        state.error!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  SizedBox(height: android ? 16 : 40),
                  const Text(
                    '1–6 pilotos · 2 voltas',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
