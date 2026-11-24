// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders Home and planet mode to build/shots (not part of the normal suite).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/word_landing.dart' show wordCheckProvider;
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/home_test_helpers.dart';
import '../test/widget_test.dart' show loadAppFonts;

void main() {
  setUpAll(loadAppFonts);
  testWidgets('shots', (tester) async {
    await tester.runAsync(GlobeArt.load);
    tester.view.physicalSize = const Size(411 * 2, 891 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final board = List<String?>.filled(kPlanetBoard * kPlanetBoard, null);
    void put(int r, int c, String w, int step) {
      for (var i = 0; i < w.length; i++) {
        board[r * kPlanetBoard + c + i * step] = w[i];
      }
    }

    put(364, 246, 'WELL', 1);
    put(361, 247, 'ROVERS', kPlanetBoard);
    Map<String, dynamic> save() => {
          'boardCells': board,
          'rackCells': List<String>.filled(10, 'E'),
          'pool': List<String>.filled(50, 'E'),
          'dealtLetters': ['E'],
          'lastCashedOutScore': 0,
          'discoveredWords': ['WELL'],
          'saveVersion': 6,
          'planetSlot': 0,
          'tidiedLoose': true,
        };
    SharedPreferences.setMockInitialValues({
      'infiniteEstateVillageSave': jsonEncode(save()),
      'p2_infiniteEstateVillageSave': jsonEncode(save()),
      'playersData': jsonEncode({
        'players': [
          {'id': 'p1', 'name': 'Me', 'colorIndex': 0},
          {'id': 'p2', 'name': 'Sam', 'colorIndex': 2},
        ],
        'currentId': 'p1',
        'nextNumber': 3,
      }),
    });
    await skipHomeIntro();
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: ProviderScope(overrides: [wordCheckProvider.overrideWithValue((w) async => true)], child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp())),
    ));
    await tester.pumpAndSettle();
    if (find.byType(GlobeView).evaluate().isEmpty) {
      await tester.tap(find.text('Me').first);
      await tester.pumpAndSettle();
    }
    Future<void> shot(String name) => tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await b.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('build/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
    await shot('pm1-home');
    await tester.tap(find.byType(GlobeView));
    await tester.pumpAndSettle();
    await shot('pm2-planet');
    await tester.drag(find.byType(GlobeView), const Offset(-240, 0));
    await tester.pumpAndSettle();
    await shot('pm3-spun');
    await tester.tap(find.text('My village').last);
    await tester.pumpAndSettle();
    await shot('pm4-found');
    await tester.tap(find.byKey(const ValueKey('globe-village-0')));
    await tester.pump();
    for (var i = 1; i <= 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      await shot('pd$i');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
