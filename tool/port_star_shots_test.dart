// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders the port, the star and the glow card to build/shots (not in the suite).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/fog.dart';
import 'package:namer_app/game/word_landing.dart' show wordCheckProvider;
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/letterra/port.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/screens/infinite_estate_screen.dart';
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
    final key = GlobalKey();
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final bytes = await (await b.toImage(pixelRatio: 1)).toByteData(format: ui.ImageByteFormat.png);
        File('build/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    final board = List<String?>.filled(kPlanetBoard * kPlanetBoard, null);
    final cells = [for (var i = 0; i < 4; i++) 369 * kPlanetBoard + 248 + i];
    for (var i = 0; i < 4; i++) {
      board[cells[i]] = 'WELL'[i];
    }
    Future<void> show(Widget home, Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues({...prefs, 'reduceMotion': true});
      await skipHomeIntro();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [wordCheckProvider.overrideWithValue((w) async => true)],
          child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: home),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await show(const MaterialApp(home: InfiniteEstateScreen()), {});
    await shot('ps1-new-words');
    await tester.tap(find.text('Village').last);
    await shot('ps2-new-village');
    final save = jsonEncode({
      'boardCells': board,
      'rackCells': List<String>.filled(10, 'E'),
      'pool': List<String>.filled(50, 'E'),
      'dealtLetters': ['E'],
      'lastCashedOutScore': 0,
      'discoveredWords': ['WELL'],
      'everUsed': cells,
      'cleared': FogMap.empty().clearAround(cells, radius: 5).toBase64(),
      'saveVersion': 6,
      'planet': {'slot': 0},
      'tidiedLoose': true,
    });
    final port = portFor(0, cells);
    await show(MaterialApp(home: InfiniteEstateScreen(focusCell: port.pier[1])), {'infiniteEstateVillageSave': save});
    await shot('ps3-port-words');
    await tester.tap(find.text('Village').last);
    await shot('ps4-port-village');
    await show(const MyApp(), {'infiniteEstateVillageSave': save});
    await tester.tap(find.byType(GlobeView));
    await shot('ps5-planet');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
