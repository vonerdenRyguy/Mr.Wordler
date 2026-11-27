// ignore_for_file: invalid_use_of_visible_for_testing_member
// Pictures of the built spec-22 screens, to build/shots (not in the suite).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/explore/fog.dart';
import 'package:namer_app/daily/word_of_the_day.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/big_test_village.dart';
import '../test/home_test_helpers.dart';
import '../test/widget_test.dart' show loadAppFonts;

void main() {
  setUpAll(loadAppFonts);
  for (final fresh in [false, true]) {
    testWidgets('shots $fresh', (tester) async {
      final letters = closeUpTestLetters();
      final board = List<String?>.filled(kPlanetBoard * kPlanetBoard, null);
      letters.forEach((k, v) => board[k] = v);
      const loose = 352 * kPlanetBoard + 246;
      if (!fresh) board[loose] ??= 'Q';
      final all = ['HOUSE', 'TOWER', 'FARM', 'MILL', 'GARDEN', 'BRIDGE', 'WELL', 'BARN'];
      SharedPreferences.setMockInitialValues({
        'infiniteEstateVillageSave': jsonEncode({
          'boardCells': board,
          'rackCells': 'ABCDERTSIN'.split(''),
          'pool': List<String>.filled(50, 'E'),
          'dealtLetters': [...letters.values, ...'ABCDERTSIN'.split('')],
          'lastCashedOutScore': 0,
          'discoveredWords': fresh ? (all..remove('TOWER')) : all,
          'saveVersion': 6,
          'planetSlot': 0,
          'tidiedLoose': true,
          'everUsed': letters.keys.toList(),
          'bandsReached': [0, 1, 2, 3],
          'cleared': FogMap.empty().clearAround(letters.keys.toList(), radius: 3).toBase64(),
          'villagers': [
            {'id': 'v0', 'name': 'Pip', 'cell': 350 * kPlanetBoard + 250, 'hearts': 2, 'movedInWord': 'CAT'},
            {'id': 'v1', 'name': 'Dot', 'cell': 346 * kPlanetBoard + 246, 'hearts': 2, 'movedInWord': 'CAT'},
          ],
        }),
      });
      await skipHomeIntro();
      await tester.runAsync(GlobeArt.load);
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.15;
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [
            wordCheckProvider.overrideWithValue((w) async => !w.contains('Q')),
            wordsOfTheDayProvider.overrideWith((ref) async => const <WordOfDay>[]),
          ],
          child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
        ),
      ));
      Future<void> settle([int n = 40]) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> shot(String name) => tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            File('build/shots/op-$name.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(bytes!.buffer.asUint8List());
          });

      await settle();
      await tester.tap(find.byKey(const ValueKey('home-my-village')));
      await settle(fresh ? 14 : 60);
      if (fresh) {
        await shot('drop');
        await settle(60);
        await shot('moment');
        await tester.pumpWidget(const SizedBox());
        return;
      }
      for (var i = 0; i < 6 && find.text('Hooray!').evaluate().isNotEmpty; i++) {
        await tester.tap(find.text('Hooray!').last);
        await settle(30);
      }
      await shot('words');
      await tester.tap(find.byKey(const ValueKey('words-planet')));
      await settle();
      await shot('streets');
      await tester.tap(find.byKey(const ValueKey('globe-zoom-out')));
      await settle(20);
      await shot('mid');
      await tester.tap(find.byKey(const ValueKey('globe-zoom-out')));
      await settle(10);
      await tester.tap(find.byKey(const ValueKey('globe-zoom-out')));
      await settle(10);
      await shot('z2');
      tester.state<GlobeViewState>(find.byType(GlobeView)).showWhole(1);
      await settle(20);
      await shot('whole');
      await tester.tap(find.byKey(const ValueKey('globe-zoom-in')));
      await settle(10);
      await tester.tap(find.byKey(const ValueKey('globe-zoom-in')));
      await settle(10);
      await shot('shore');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
