// spec-18 commit 4: the village on Letterra: sea and bays refuse tiles, band
// word lengths by level, the band chip, and an old village landing on the
// shore with every letter where it was (plus the offset).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/island_map.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/letterra/band_info.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/settings/word_level.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart' show skipHomeIntro;

const _size = 500;
const _mid = _size ~/ 2;
const _key = 'infiniteEstateVillageSave';

int _c(int r, int c) => r * _size + c;

void main() {
  final map = IslandMap.letterra(seed: 15001);

  group('drops', () {
    test('the Deep and open bays are sea; your harbor and the shore are not', () {
      expect(map.isSeaIndex(_c(_mid + 130, _mid)), isTrue); // the Deep
      expect(map.isSeaIndex(_c(-1, 5)), isTrue);
      final own = harborCell(0);
      expect(map.isSeaIndex(own), isFalse);
      expect(map.isSeaIndex(harborCell(4)), isTrue); // an open bay
      expect(map.isSeaIndex(_c(_mid + 100, _mid + 41)), isFalse); // meadow between
    });

    test('with every spot taken there are no bays, only the Deep', () {
      final full = IslandMap.letterra(seed: 15001, takenSlots: takenSlotsFor(8));
      expect(full.isSeaIndex(harborCell(4)), isFalse);
      expect(full.isSeaIndex(_c(_mid + 130, _mid)), isTrue);
    });
  });

  group('band lengths by level', () {
    test('Woods ask 4+ (3 for Sprout), Hills 6+, Mountains 7+ (4 for Sprout)', () {
      expect(bandMinLength(Band.sunnyShore, WordLevel.wordsmith), 3);
      expect(bandMinLength(Band.meadow, WordLevel.wordsmith), 3);
      expect(bandMinLength(Band.whisperWoods, WordLevel.wordsmith), 4);
      expect(bandMinLength(Band.whisperWoods, WordLevel.sprout), 3);
      expect(bandMinLength(Band.ribbonRiver, WordLevel.wordsmith), 5);
      expect(bandMinLength(Band.ruinHills, WordLevel.wordsmith), 6);
      expect(bandMinLength(Band.echoMountains, WordLevel.wordsmith), 7);
      expect(bandMinLength(Band.echoMountains, WordLevel.sprout), 4);
      expect(bandMinLength(Band.cloudCap, WordLevel.wordsmith), isNull);
      expect(bandMinLength(Band.deep, WordLevel.wordsmith), isNull);
    });

    test('chip text names the band and its length', () {
      expect(bandChipText(Band.whisperWoods, WordLevel.wordsmith), 'Whisper Woods · 4+ letters');
      expect(bandChipText(Band.ribbonRiver, WordLevel.builder), 'Ribbon River · 5+ letters to cross');
      expect(bandChipText(Band.deep, WordLevel.wordsmith), 'The Deep · open sea');
      expect(bandChipText(Band.meadow, WordLevel.wordsmith, bay: true), 'Open bay · sea');
    });
  });

  testWidgets('an old village lands on the shore, words where they were plus the offset', (tester) async {
    final board = List<String?>.filled(_size * _size, null);
    'WELL'.split('').asMap().forEach((i, l) => board[_c(_mid, _mid - 2 + i)] = l);
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode({
        'boardCells': board,
        'rackCells': List<String>.filled(10, 'E'),
        'pool': List<String>.filled(50, 'E'),
        'dealtLetters': ['W', 'E', 'L', 'L', ...List<String>.filled(10, 'E')],
        'lastCashedOutScore': 0,
        'discoveredWords': ['WELL'],
        'saveVersion': 5,
        'tidiedLoose': true,
        'looseNote': 0,
      }),
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await skipHomeIntro();
    await tester.pumpWidget(ProviderScope(
      overrides: [wordCheckProvider.overrideWithValue((w) async => w == 'WELL')],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('globe-village-0')));
    await tester.pumpAndSettle();

    // The band chip says where the view is centred: the Sunny Shore.
    expect(find.text('Sunny Shore · 3+ letters'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final json = jsonDecode(prefs.getString(_key)!) as Map<String, dynamic>;
    expect(json['saveVersion'], 6);
    expect(json['planet'], {'slot': 0, 'migratedFrom': 5});
    final cells = json['boardCells'] as List;
    for (var i = 0; i < 4; i++) {
      expect(cells[_c(_mid + 120, _mid - 2 + i)], 'WELL'[i]);
      expect(cells[_c(_mid, _mid - 2 + i)], isNull);
    }
  });
}
