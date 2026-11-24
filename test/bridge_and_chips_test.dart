// Bridge jumps to found landmarks and shrines; the chip row (with the
// villagers chip) still fits two rows at text size 1.15 on the Samsung.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/word_of_the_day.dart';
import 'package:namer_app/explore/island_map.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/screens/infinite_estate_screen.dart';
import 'package:namer_app/ui/pill_chip.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/village/village_save.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart' show skipHomeIntro;
import 'widget_test.dart' show loadAppFonts;

const _size = 500;
const _mid = _size ~/ 2;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Bridge lists found shrines and landmarks; chips fit two rows at 1.15', (tester) async {
    final map = IslandMap(seed: VillageSaveData.kDefaultMapSeed, homes: const [InfiniteEstateScreen.homeIndex]);
    final shrine = map.specials.firstWhere((s) => s.kind == SpecialKind.shrine);
    final oak = map.specials.firstWhere((s) => s.landmark == LandmarkKind.giantOak);
    final board = List<String?>.filled(_size * _size, null);
    'BRIDGE'.split('').asMap().forEach((i, l) => board[(_mid + 3) * _size + _mid - 3 + i] = l);
    'TOWER'.split('').asMap().forEach((i, l) => board[(_mid + 8) * _size + _mid - 3 + i] = l);
    'WELL'.split('').asMap().forEach((i, l) => board[(_mid - 3) * _size + _mid - 3 + i] = l);
    SharedPreferences.setMockInitialValues({
      'infiniteEstateVillageSave': jsonEncode({
        'boardCells': board,
        'rackCells': List<String>.filled(10, 'E'),
        'pool': List<String>.filled(50, 'E'),
        'dealtLetters': List<String>.filled(30, 'E'),
        'lastCashedOutScore': 0,
        'discoveredWords': ['BRIDGE', 'WELL', 'TOWER'],
        'saveVersion': 4,
        'cleared': '',
        'foundSpecials': [shrine.id, oak.id],
        'villagers': [
          {'id': 'v0', 'name': 'Pip', 'cell': map.villagers.first.cell, 'hearts': 1, 'granted': 1, 'movedInWord': 'WELL', 'nextWishOn': '2999-01-01'},
        ],
      }),
    });
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await skipHomeIntro();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wordCheckProvider.overrideWithValue((w) async => {'BRIDGE', 'WELL', 'TOWER'}.contains(w.toUpperCase())),
        wordsOfTheDayProvider.overrideWith((ref) async => const []),
      ],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-my-village')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 20));
    // Building moments (Well, Bridge) may be open; close them.
    for (var i = 0; i < 5 && find.text('Hooray!').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('Hooray!'));
      await tester.pumpAndSettle();
    }

    // Chip row: at most two rows, no overflow, villagers chip there.
    final chips = find.byType(PillChip);
    final tops = {for (final e in chips.evaluate()) tester.getTopLeft(find.byWidget(e.widget)).dy.round()};
    expect(tops.length, lessThanOrEqualTo(2), reason: 'chip rows at $tops');
    expect(find.text('1/12'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Bridge chip -> found places.
    await tester.tap(find.text('Jump'));
    await tester.pumpAndSettle();
    expect(find.text('Bridge: jump to...'), findsOneWidget);
    expect(find.text(shrine.shrine!.displayName), findsOneWidget);
    expect(find.text('Giant Oak'), findsOneWidget);
    await tester.tap(find.text('Giant Oak'));
    await tester.pumpAndSettle();
    expect(find.text('Bridge: jump to...'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
