// spec-18b commits 4-6: the port, the gold star, something to find and the
// new region celebration.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/fog.dart';
import 'package:namer_app/explore/island_map.dart';
import 'package:namer_app/explore/regions.dart';
import 'package:namer_app/game/grid_board_widget.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/tile_location.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/letterra/gold_star.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/letterra/port.dart';
import 'package:namer_app/letterra/port_view.dart';
import 'package:namer_app/letterra/something_to_find.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/screens/infinite_estate_screen.dart';
import 'package:namer_app/settings/word_level.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/village/village_save.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart';
import 'widget_test.dart' show loadAppFonts;

const _key = 'infiniteEstateVillageSave';
const _seed = VillageSaveData.kDefaultMapSeed;

int _c(int r, int c) => r * kPlanetBoard + c;

Map<String, dynamic> _save(Map<int, String> letters) {
  final board = List<String?>.filled(kPlanetBoard * kPlanetBoard, null);
  letters.forEach((i, l) => board[i] = l);
  return {
    'boardCells': board,
    'rackCells': List<String>.filled(10, 'E'),
    'pool': List<String>.filled(50, 'E'),
    'dealtLetters': [...letters.values, ...List<String>.filled(10, 'E')],
    'lastCashedOutScore': 0,
    'discoveredWords': <String>[],
    'everUsed': letters.keys.toList(),
    'saveVersion': 6,
    'planet': {'slot': 0},
    'tidiedLoose': true,
  };
}

Map<int, String> _word(String w, int cell) => {for (var i = 0; i < w.length; i++) cell + i: w[i]};

void main() {
  setUpAll(loadAppFonts);

  group('port', () {
    test('every harbor: pier, boat and flag are all on sea, never on land', () {
      for (var slot = 0; slot < kHarborSlots; slot++) {
        final map = IslandMap.letterra(seed: _seed, slot: slot);
        final home = harborCell(slot);
        for (final letters in [
          <int>[],
          [home],
          [home - 8 * kPlanetBoard + 30],
          [home + 40],
          [home - 60],
        ]) {
          final p = portFor(slot, letters);
          expect(p.pier.toSet(), hasLength(5));
          expect(p.pier, isNot(contains(p.boat)));
          for (final i in [...p.pier, p.boat]) {
            expect(map.isSeaIndex(i), isTrue, reason: 'slot $slot cell $i');
          }
        }
      }
    });

    test('it faces the letters, inside its own wedge', () {
      expect(portAngle(0, []), 0);
      expect(portAngle(0, [_c(366, 260)]), greaterThan(0));
      expect(portAngle(0, [_c(250, 400)]).abs(), lessThan(slotAngle(1) / 2));
    });
  });

  group('gold star', () {
    test('every harbor: on land', () {
      for (var slot = 0; slot < kHarborSlots; slot++) {
        final map = IslandMap.letterra(seed: _seed, slot: slot);
        final cell = goldStarCell(slot, isSea: map.isSeaIndex);
        expect(map.isSeaIndex(cell), isFalse);
      }
    });

    test('a taken or sea harbor square moves it to the nearest free land', () {
      final home = harborCell(0);
      final cell = goldStarCell(0, isSea: (i) => i == home - 1, taken: {home});
      expect(cell, isNot(anyOf(home, home - 1)));
      expect((cell ~/ kPlanetBoard - home ~/ kPlanetBoard).abs(), lessThanOrEqualTo(1));
    });

    test('older saves have no star, and nothing is written for them', () {
      final s = VillageSaveData.fromJson(_save({}));
      expect(s.starActive, isFalse);
      expect(s.bandsReached, isNull);
      expect(s.toJson().keys, isNot(contains('starStart')));
      expect(s.toJson().keys, isNot(contains('bandsReached')));
    });

    test('star and regions survive a save', () {
      final json = _save({})
        ..['starStart'] = true
        ..['bandsReached'] = [0, 1];
      final s = VillageSaveData.fromJson(jsonDecode(jsonEncode(VillageSaveData.fromJson(json).toJson())));
      expect(s.starActive, isTrue);
      expect(s.bandsReached, {0, 1});
      expect(s.copyWith(saveVersion: 6).starActive, isTrue);
    });
  });

  group('something to find', () {
    final map = IslandMap.letterra(seed: _seed, slot: 0);
    test('the nearest one, its distance and its word length', () {
      final near = _c(366, 250), far = _c(340, 250);
      final f = thingsToFind(
          map: map, unfound: [far, near], letters: [_c(366, 245)], level: WordLevel.wordsmith).first;
      expect(f.cell, near);
      expect(f.squares, 5);
      expect(f.region, 'the Meadow');
      expect(f.minLength, 3);
    });
    test('words for the Woods follow the word level', () {
      final woods = _c(330, 250);
      SomethingToFind at(WordLevel l) => thingsToFind(map: map, unfound: [woods], letters: [], level: l).single;
      expect(at(WordLevel.wordsmith).region, 'the Woods');
      expect(at(WordLevel.wordsmith).minLength, 4);
      expect(at(WordLevel.sprout).minLength, 3);
    });
    test('nothing left, nothing at sea', () {
      expect(thingsToFind(map: map, unfound: [], letters: [], level: WordLevel.sprout), isEmpty);
      expect(thingsToFind(map: map, unfound: [_c(490, 250)], letters: [], level: WordLevel.sprout), isEmpty);
    });
    test('a new village has something, and it can be reached', () {
      final f = thingsToFind(
          map: map, unfound: map.specials.map((s) => s.cell), letters: [], level: WordLevel.wordsmith).first;
      expect(f.minLength, lessThan(10));
    });
  });

  test('regionsCleared names only land with cleared fog', () {
    expect(regionsCleared(FogMap.empty()), isEmpty);
    expect(regionsCleared(FogMap.empty().clearAround([_c(360, 250)], radius: 1)), {1});
    expect(regionsCleared(FogMap.empty().clearAround([_c(490, 250)], radius: 1)), isEmpty);
  });

  // ── In the app ─────────────────────────────────────────────────────────────

  Future<void> start(WidgetTester tester, {Map<String, dynamic>? save}) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({if (save != null) _key: jsonEncode(save), 'reduceMotion': true});
    await skipHomeIntro();
    await tester.pumpWidget(ProviderScope(
      overrides: [wordCheckProvider.overrideWithValue((w) async => true)],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home-my-village')));
    await tester.pumpAndSettle();
  }

  ProviderContainer box(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(GridRackView)));

  Future<void> put(WidgetTester tester, int rackIndex, int cell) async {
    box(tester).read(gridGameControllerProvider.notifier).moveTile(TileLocation(TileZone.rack, rackIndex), TileLocation(TileZone.board, cell));
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>> saved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return jsonDecode(prefs.getString(_key)!) as Map<String, dynamic>;
  }

  // Letters at [cell] and beside it, as one two-letter word.
  Future<void> pair(WidgetTester tester, int cell) async {
    await put(tester, 0, cell);
    await put(tester, 1, cell + 1);
  }

  Future<void> closeMoments(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      for (final label in ['Collect', 'Hooray!', 'Got it', 'Great!']) {
        if (find.text(label).evaluate().isNotEmpty) {
          await tester.tap(find.text(label).first);
          await tester.pumpAndSettle();
        }
      }
    }
  }

  testWidgets('a new village: a word off the star waits, one on it counts, then the star is only a mark',
      (tester) async {
    await start(tester);
    await enter(tester);
    expect(find.text('Your first word must cover the gold star'), findsOneWidget);
    expect(find.byType(GoldStarMark), findsOneWidget);
    expect(box(tester).read(startCellProvider), isNotNull);
    final star = box(tester).read(startCellProvider)!;

    // Off the star: both letters stay put but nothing counts.
    final off = star - 3 * kPlanetBoard;
    await pair(tester, off);
    expect((await saved())['starStart'], isTrue);
    expect((await saved())['everUsed'], isEmpty);
    expect(box(tester).read(gridGameControllerProvider).boardCells[off], isNotNull);
    expect(find.text('Your first word must cover the gold star'), findsOneWidget);

    // On the star.
    await pair(tester, star);
    await closeMoments(tester);
    expect(find.text('Your first word must cover the gold star'), findsNothing);
    var s = await saved();
    expect(s['starDone'], isTrue);
    expect(s['everUsed'], containsAll([star, star + 1, off, off + 1]));

    // Taking the word away later changes nothing.
    final c = box(tester).read(gridGameControllerProvider.notifier);
    c.moveTile(TileLocation(TileZone.board, star), TileLocation(TileZone.board, star - 6));
    await tester.pumpAndSettle();
    c.moveTile(TileLocation(TileZone.board, star + 1), TileLocation(TileZone.board, star - 5));
    await tester.pumpAndSettle();
    await closeMoments(tester);
    s = await saved();
    expect(s['starDone'], isTrue);
    expect(find.text('Your first word must cover the gold star'), findsNothing);
    expect(box(tester).read(startCellProvider), isNull);
  });

  testWidgets('an old village has no star and gets no pile of celebrations', (tester) async {
    await start(tester, save: _save(_word('WELL', _c(366, 248))));
    await enter(tester);
    await closeMoments(tester);
    expect(find.byType(GoldStarMark), findsNothing);
    expect(find.text('New region!'), findsNothing);
    final s = await saved();
    expect(s.containsKey('starStart'), isFalse);
    expect(s['bandsReached'], isNotEmpty);
    for (var i = 0; i < 4; i++) {
      expect((s['boardCells'] as List)[_c(366, 248 + i)], 'WELL'[i]);
    }
  });

  testWidgets('reaching the Woods is celebrated once, with coins', (tester) async {
    final save = _save(_word('WELL', _c(345, 248)))..['bandsReached'] = [0, 1];
    await start(tester, save: save);
    await enter(tester);
    await closeMoments(tester);
    // A four-letter word up in the Woods.
    for (var i = 0; i < 4; i++) {
      await put(tester, i, _c(338, 248 + i));
      if (i < 3) await closeMoments(tester);
    }
    expect(find.text('You reached the Woods!'), findsOneWidget);
    await closeMoments(tester);
    expect((await saved())['bandsReached'], contains(2));
    for (var i = 0; i < 4; i++) {
      await put(tester, 5 + i, _c(338, 254 + i));
    }
    expect(find.text('You reached the Woods!'), findsNothing);
  });

  testWidgets('planet mode says what glows, and Show me opens the village there', (tester) async {
    await start(tester, save: _save(_word('WELL', _c(366, 248))));
    await tester.tap(find.byType(GlobeView));
    await tester.pumpAndSettle();
    expect(find.textContaining('Something glows in the'), findsOneWidget);
    expect(find.textContaining('letters or more'), findsOneWidget);
    expect(find.text('My village'), findsOneWidget);
    // The zoom buttons sit above the card.
    final card = tester.getRect(find.textContaining('Something glows'));
    expect(tester.getRect(find.byKey(const ValueKey('globe-zoom-in'))).bottom, lessThan(card.top));
    await tester.tap(find.textContaining('Something glows'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('globe-glow')), findsOneWidget);
    await tester.tap(find.text('Show me'));
    await tester.pumpAndSettle();
    final estate = tester.widget<InfiniteEstateScreen>(find.byType(InfiniteEstateScreen));
    expect(estate.focusCell, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the Shrine of Sight three things glow', (tester) async {
    final save = _save(_word('WELL', _c(366, 248)))..['shrines'] = ['sight'];
    await start(tester, save: save);
    await tester.tap(find.byType(GlobeView));
    await tester.pumpAndSettle();
    expect(tester.widget<GlobeView>(find.byType(GlobeView)).glowCells.toSet(), hasLength(3));
  });

  testWidgets('nothing left to find: no glow, just Find my village', (tester) async {
    final map = IslandMap.letterra(seed: _seed, slot: 0);
    final save = _save(_word('WELL', _c(366, 248)))
      ..['foundSpecials'] = [for (final s in map.specials) s.id]
      ..['villagers'] = [
        for (final s in map.specials)
          if (s.kind == SpecialKind.villager) {'id': s.id, 'name': s.id, 'cell': s.cell},
      ];
    await start(tester, save: save);
    await tester.tap(find.byType(GlobeView));
    await tester.pumpAndSettle();
    expect(find.text('Find my village'), findsOneWidget);
    expect(find.byKey(const ValueKey('globe-glow')), findsNothing);
  });
}
