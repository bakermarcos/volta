import 'dart:io';
import 'dart:math' as math;

import 'package:volta/room/session.dart';
import 'package:volta/room/race_history.dart';
import 'package:volta/game/race.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volta/main.dart';
import 'package:volta/ui/race_scene.dart';

void main() {
  testWidgets(
    'TV mode asks the Mac window for fullscreen and can be switched off',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <MethodCall>[];
      const channel = MethodChannel('volta/window');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(const VoltaApp());
      await tester.tap(find.text('Modo TV · tela cheia'));
      await tester.pump();
      expect(calls.single.method, 'fullscreen');
      expect(calls.single.arguments, true);
      await tester.tap(find.text('Sair do modo TV'));
      await tester.pump();
      expect(calls.last.arguments, false);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'solo lobby reuses scene, counts down and confirms pause on second click',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const VoltaApp());
      await tester.tap(find.text('Treinar com teclado'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Lima'), findsOneWidget);
      expect(find.text('Azul'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Brasil'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(
        find.text('Austrália'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('circuit-grid')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Austrália'));
      await tester.pump(const Duration(milliseconds: 500));
      final before = tester.state(find.byType(RaceScene));
      await tester.tap(find.text('Largar  →'));
      await tester.pump();
      expect(find.text('Pronto'), findsNothing);
      final opening = tester.widget<RaceScene>(find.byType(RaceScene));
      for (var i = 0; i < 10; i++) {
        opening.onAdvance!(.05);
      }
      await tester.pump();
      expect(find.text('Pronto'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        opening.onAdvance!(.05);
      }
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(tester.getSize(find.byType(RaceScene)), const Size(1280, 820));
      expect(tester.state(find.byType(RaceScene)), same(before));
      expect(
        tester.widget<RaceScene>(find.byType(RaceScene)).race!.circuit.name,
        'Austrália',
      );
      final scene = tester.widget<RaceScene>(find.byType(RaceScene));
      for (var i = 0; i < 70; i++) {
        scene.onAdvance!(.05);
      }
      await tester.pump();
      expect(scene.race!.elapsed, closeTo(.5, .1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Corrida pausada'), findsNothing);
      expect(find.text('Pausar'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      final pausedAt = scene.race!.elapsed;
      scene.onAdvance!(.05);
      expect(scene.race!.elapsed, pausedAt);
      await tester.tap(find.text('Continuar'));
      await tester.pump(const Duration(milliseconds: 300));
      scene.onAdvance!(.05);
      expect(scene.race!.elapsed, greaterThan(pausedAt));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'solo finish celebrates, saves times and returns to configured lobby',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('volta-finish'),
      ))!;
      addTearDown(
        () => tester.runAsync(() => directory.delete(recursive: true)),
      );
      final session = (await tester.runAsync(() async {
        final session = Session(
          history: RaceHistory(file: File('${directory.path}/races.json')),
        );
        await session.ready;
        return session;
      }))!;
      await tester.pumpWidget(VoltaApp(session: session));
      await tester.tap(find.text('Treinar com teclado'));
      await tester.pump();
      await tester.tap(find.text('Configurações'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Diminuir voltas'));
      await tester.tap(find.text('Aplicar configurações'));
      await tester.pump(const Duration(milliseconds: 500));
      final state = tester.state(find.byType(RaceScene));
      await tester.tap(find.text('Largar  →'));
      await tester.pump();
      final scene = tester.widget<RaceScene>(find.byType(RaceScene));
      for (var i = 0; i < 20; i++) {
        scene.onAdvance!(.05);
      }
      await tester.pump();
      for (var second = 0; second < 3; second++) {
        expect(tester.getSize(find.byType(RaceScene)), const Size(1280, 820));
        for (var frame = 0; frame < 20; frame++) {
          scene.onAdvance!(.05);
        }
        await tester.pump();
      }
      scene.onAdvance!(.05);
      final race = scene.race!, car = scene.race!.cars.first;
      await tester.runAsync(() async {
        for (var i = 0; i < checkpointCount; i++) {
          final gate = race.checkpoints[car.nextCheckpoint];
          car.trackAngle = car.nextCheckpoint * math.pi * 2 / checkpointCount;
          car.x = gate.x - gate.forwardX;
          car.y = gate.y - gate.forwardY;
          car.heading = math.atan2(gate.forwardY, gate.forwardX);
          car.speed = 200;
          scene.onAdvance!(.02);
        }
        await session.finish(race);
      });
      await tester.pump();
      expect(find.text('Lima VENCEU!'), findsOneWidget);
      expect(session.history.races.length, 1);
      expect(car.lapTimes.length, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Voltar ao lobby  →'));
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(find.text('Largar  →'), findsOneWidget);
      expect(tester.state(find.byType(RaceScene)), same(state));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'TV lobby supports directional focus and race settings at 960x540',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = Session()..tvMode = true;
      session.local();
      await tester.pumpWidget(VoltaApp(session: session));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Espanha'),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Espanha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Configurações da corrida'), findsOneWidget);
      await tester.ensureVisible(find.text('Modo turbo'));
      await tester.tap(find.text('Modo turbo'));
      await tester.ensureVisible(find.text('Sentido inverso'));
      await tester.tap(find.text('Sentido inverso'));
      await tester.ensureVisible(find.text('Espelhar traçado'));
      await tester.tap(find.text('Espelhar traçado'));
      await tester.ensureVisible(find.text('Aplicar configurações'));
      await tester.tap(find.text('Aplicar configurações'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('Largar  →'));
      await tester.tap(find.text('Largar  →'));
      await tester.pump();
      final race = tester.widget<RaceScene>(find.byType(RaceScene)).race!;
      expect(race.turbo && race.reversed && race.mirrored, true);
      expect(race.circuit.name, 'Espanha');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
