// Villagers in the village screen (spec-16): a word on their square brings
// them home and you name them; a spelled wish pays once.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/word_of_the_day.dart';
import 'package:namer_app/explore/island_map.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/portfolio/portfolio_controller.dart';
import 'package:namer_app/screens/infinite_estate_screen.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/village/village_save.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart' show skipHomeIntro;

const _size = 500;

IslandMap get _map => IslandMap(seed: VillageSaveData.kDefaultMapSeed, homes: const [InfiniteEstateScreen.homeIndex]);

/// Puts [word] across on [cell]'s row, starting [before] squares left of it.
void _across(List<String?> board, int cell, String word, {int before = 1}) {
  final start = cell - before;
  word.split('').asMap().forEach((i, l) => board[start + i] = l);
}

Map<String, dynamic> _save(List<String?> board, {int version = 3, List<dynamic>? villagers}) => {
      'boardCells': board,
      'rackCells': List<String>.filled(10, 'E'),
      'pool': List<String>.filled(50, 'E'),
      'dealtLetters': List<String>.filled(30, 'E'),
      'lastCashedOutScore': 0,
      'discoveredWords': <String>[],
      'saveVersion': version,
      if (version >= 3) 'cleared': '',
      if (villagers != null) 'villagers': villagers,
    };

void main() {
  Future<ProviderContainer> openVillage(WidgetTester tester, Map<String, dynamic> save, Set<String> validWords) async {
    SharedPreferences.setMockInitialValues({'infiniteEstateVillageSave': jsonEncode(save)});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await skipHomeIntro();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wordCheckProvider.overrideWithValue((w) async => validWords.contains(w.toUpperCase())),
        wordsOfTheDayProvider.overrideWith((ref) async => const []),
      ],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.text('Visit your village')));
    await tester.tap(find.text('Visit your village'));
    await tester.pumpAndSettle(
        const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 20));
    return container;
  }

  testWidgets('a word on the villager\'s square brings them home; any typed name is kept', (tester) async {
    final tile = _map.villagers.first;
    final board = List<String?>.filled(_size * _size, null);
    _across(board, tile.cell, 'SIPS');
    final container = await openVillage(tester, _save(board), {'SIPS'});

    expect(find.text('Someone moved in!'), findsOneWidget);
    expect(find.textContaining('Your word SIPS reached them'), findsOneWidget);
    await tester.tap(find.text('Meet them'));
    await tester.pumpAndSettle();

    // The naming sheet: a ready name, 3 other picks, and a box for any name.
    expect(find.text('What\'s their name?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Captain Zed');
    await tester.pump();
    expect(find.text('Welcome home, Captain Zed!'), findsOneWidget);
    await tester.tap(find.text('Welcome home, Captain Zed!'));
    await tester.pumpAndSettle();

    expect(find.text('What\'s their name?'), findsNothing);
    // The chip appears, and the save holds the villager with a first wish.
    expect(find.text('1/12'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('infiniteEstateVillageSave')!) as Map<String, dynamic>;
    expect(saved['saveVersion'], 6);
    final v = (saved['villagers'] as List).single as Map<String, dynamic>;
    expect(v['id'], tile.id);
    expect(v['name'], 'Captain Zed');
    expect(v['cell'], tile.cell);
    expect(v['movedInWord'], 'SIPS');
    expect(v['wish'], isNotNull);
    expect(tester.takeException(), isNull);
    expect(container.read(portfolioProvider).currency, 0);

    // In Words view they stand beside the word; tap for the card.
    final standing = find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Captain Zed, villager'));
    expect(standing, findsOneWidget);
    await tester.tap(standing);
    await tester.pumpAndSettle();
    expect(find.text('Captain Zed wishes for'), findsOneWidget);
    expect(find.text('Another idea'), findsOneWidget);
    await tester.tap(find.text('Another idea'));
    await tester.pump();
    expect(find.text('Idea:'), findsOneWidget);
    await tester.tap(find.text('Different wish'));
    await tester.pump();
    expect(find.text('Captain Zed wishes for'), findsOneWidget);
    await tester.tap(find.textContaining('try!'));
    await tester.pumpAndSettle();

    // The Your villagers page lists them, with the fog count for the rest.
    await tester.tap(find.text('1/12'));
    await tester.pumpAndSettle();
    expect(find.text('Your villagers'), findsOneWidget);
    expect(find.text('Captain Zed'), findsOneWidget);
    expect(find.text('1 of 12'), findsOneWidget);
    expect(find.text('4 in the Forest, 4 in the Hills, 3 in the Mountains'), findsOneWidget);
  });

  testWidgets('a 2-letter word on their square does not bring them home yet', (tester) async {
    final tile = _map.villagers.first;
    final board = List<String?>.filled(_size * _size, null);
    _across(board, tile.cell, 'SI');
    await openVillage(tester, _save(board), {'SI'});
    expect(find.text('Someone moved in!'), findsNothing);
    expect(find.text('1/12'), findsNothing);
  });

  testWidgets('a wish already answered by a word on the board comes true once: heart, coins, XP', (tester) async {
    final tile = _map.villagers.first;
    final board = List<String?>.filled(_size * _size, null);
    // The villager's square holds a letter of SIPS so they're already home;
    // MOONS elsewhere on the board answers their wish for a 5-letter word.
    _across(board, tile.cell, 'SIPS');
    _across(board, _size * 249 + 245, 'MOONS');
    final villager = {
      'id': tile.id,
      'name': 'Pip',
      'cell': tile.cell,
      'hearts': 0,
      'wish': {'k': 'length', 'n': 5, 'f': true},
      'granted': 0,
      'movedInWord': 'SIPS',
      'presentClaimed': false,
    };
    final container = await openVillage(tester, _save(board, version: 4, villagers: [villager]), {'SIPS', 'MOONS'});

    expect(find.text('Wish came true!'), findsOneWidget);
    expect(find.textContaining('Pip wished for a 5-letter word, and MOONS did it.'), findsOneWidget);
    expect(container.read(portfolioProvider).currency, 5);
    await tester.tap(find.text('Hooray!'));
    await tester.pumpAndSettle();
    expect(find.text('Wish came true!'), findsNothing);
    expect(container.read(portfolioProvider).totalXp, greaterThanOrEqualTo(10));

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('infiniteEstateVillageSave')!) as Map<String, dynamic>;
    final v = (saved['villagers'] as List).single as Map<String, dynamic>;
    expect(v['hearts'], 1);
    expect(v['granted'], 1);
    expect(v.containsKey('wish'), isFalse);
    expect(v['nextWishOn'], isNotNull);

    // The card says a new wish comes tomorrow, and Different wish is off.
    await tester.tap(find.text('1/12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pip'));
    await tester.pumpAndSettle();
    expect(find.text('A new wish comes tomorrow.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
