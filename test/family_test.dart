// A family on one phone (spec-07): players with their own saves, the
// family word, and the screens for switching players.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:namer_app/daily/daily_puzzle.dart';
import 'package:namer_app/daily/word_of_the_day.dart';
import 'package:namer_app/dictionary/definition_service.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/tile_location.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/players/family_word.dart';
import 'package:namer_app/players/players.dart';
import 'package:namer_app/portfolio/portfolio_controller.dart';
import 'package:namer_app/settings/settings_controller.dart';
import 'package:namer_app/settings/word_level.dart';
import 'package:namer_app/ui/game_layout.dart';
import 'package:namer_app/util/theme_notifier.dart';

import 'home_test_helpers.dart';

class _NoDefinitions extends DefinitionService {
  @override
  Future<String?> getDefinition(String word) async => null;
}

Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  await load('LilitaOne', ['assets/fonts/LilitaOne-Regular.ttf']);
  await load('Atkinson', ['assets/fonts/AtkinsonHyperlegible-Regular.ttf', 'assets/fonts/AtkinsonHyperlegible-Bold.ttf']);
}

final _words = parseWordsOfTheDay(File('assets/words/word_of_the_day.json').readAsStringSync());
final _day = DateTime.utc(2026, 11, 15, 12);
const _four = ['p1', 'p2', 'p3', 'p4'];

String _playersJson(List<List<Object>> players, {String current = 'p1'}) => jsonEncode({
      'players': [
        for (final p in players) {'id': p[0], 'name': p[1], 'colorIndex': p[2]},
      ],
      'currentId': current,
      'nextNumber': players.length + 1,
    });

Future<void> _pumpFor(WidgetTester tester, [int times = 6]) async {
  for (int i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(_loadAppFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlayerKeys.prefix = '';
  });
  tearDown(() => PlayerKeys.prefix = '');

  test('the family word is never the Word of the day, and its letters come out in a fixed mixed order', () {
    for (int d = 0; d < 120; d++) {
      final date = _day.add(Duration(days: d));
      expect(familyWordFor(date, _words).word, isNot(wordOfDayFor(date, _words).word));
    }
    final word = familyWordFor(_day, _words).word;
    final order = familyRevealOrder(word, _day);
    expect(order.toSet(), {for (int i = 0; i < word.length; i++) i});
    expect(familyRevealOrder(word, _day), order);
  });

  test('each finished Daily uncovers a fair share, and the last player uncovers the rest', () async {
    final family = FamilyWordController();
    await family.ready;
    const word = 'LANTERN'; // 7 letters, 4 players: 2 + 2 + 2 + 1

    List<int> play(String id) => family.recordPlayed(playerId: id, now: _day, word: word, playerIds: _four);

    expect(play('p1').length, 2);
    expect(play('p1'), isEmpty, reason: 'playing twice finds nothing new');
    expect(play('p3').length, 2);
    expect(family.state.solved, isFalse);
    expect(play('p2').length, 2);
    expect(family.state.revealed.length, 6);
    expect(play('p4').length, 1);

    expect(family.state.revealed.length, 7);
    expect(family.state.solved, isTrue);
    expect(family.state.solvedEarly, isFalse);
    expect(family.state.owed, {for (final id in _four) id: kFamilyWordCoins});
    expect(family.state.finderOf(family.state.found['p3']!.first), 'p3');
  });

  test('a right guess finds it early for more coins; a wrong one changes nothing', () async {
    final family = FamilyWordController();
    await family.ready;
    family.recordPlayed(playerId: 'p1', now: _day, word: 'LANTERN', playerIds: _four);

    expect(family.guess(text: 'candle', now: _day, word: 'LANTERN', playerIds: _four), isFalse);
    expect(family.state.solved, isFalse);
    expect(family.guess(text: ' lantern ', now: _day, word: 'LANTERN', playerIds: _four), isTrue);
    expect(family.state.solvedEarly, isTrue);
    expect(family.state.owed, {for (final id in _four) id: kFamilyWordEarlyCoins});
    expect(family.state.streak, 1);
    expect(family.state.total, 1);

    // Coins are handed over once, when that player next holds the phone.
    expect(family.claimOwed('p2'), kFamilyWordEarlyCoins);
    expect(family.claimOwed('p2'), 0);

    // Saved, and the next day starts clean but keeps coins and the streak.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final reopened = FamilyWordController();
    await reopened.ready;
    final tomorrow = _day.add(const Duration(days: 1));
    final next = reopened.today(tomorrow);
    expect(next.solved, isFalse);
    expect(next.found, isEmpty);
    expect(next.owed.keys.toSet(), {'p1', 'p3', 'p4'});
    reopened.guess(text: 'kettle', now: tomorrow, word: 'KETTLE', playerIds: _four);
    expect(reopened.state.streak, 2);
    expect(reopened.state.total, 2);
  });

  test('a new player gets their own saves; the first player keeps the old ones', () async {
    SharedPreferences.setMockInitialValues({
      'portfolioData': jsonEncode({'totalXp': 196, 'currency': 3}),
    });
    final players = PlayersController();
    await players.ready;
    expect(players.state.players.single.id, kFirstPlayerId);
    expect(players.state.isFamily, isFalse);

    final leo = (await players.add(name: ' Leo ', colorIndex: 3, level: WordLevel.sprout))!;
    expect(leo.name, 'Leo');
    expect(leo.prefix, 'p2_');
    expect(players.state.isFamily, isTrue);

    // Player one still reads the save that was there before.
    final mine = PortfolioController();
    await mine.ready;
    expect(mine.state.currency, 3);

    await players.select(leo.id);
    expect(PlayerKeys.prefix, 'p2_');
    final leos = PortfolioController();
    await leos.ready;
    expect(leos.state.currency, 0);
    leos.addCurrency(7);
    final leoSettings = SettingsController();
    await leoSettings.ready;
    expect(leoSettings.state.wordLevel, WordLevel.sprout);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final prefs = await SharedPreferences.getInstance();
    expect((jsonDecode(prefs.getString('p2_portfolioData')!) as Map)['currency'], 7);
    expect((jsonDecode(prefs.getString('portfolioData')!) as Map)['currency'], 3);

    // The players, and who had the phone, survive a restart.
    PlayerKeys.prefix = '';
    final reopened = PlayersController();
    await reopened.ready;
    expect(reopened.state.players.map((p) => p.name), ['Me', 'Leo']);
    expect(reopened.state.currentId, leo.id);
    expect(PlayerKeys.prefix, 'p2_');
  });

  test('a phone holds at most six players', () async {
    final players = PlayersController();
    await players.ready;
    for (int i = 0; i < 5; i++) {
      expect(await players.add(name: 'P$i', colorIndex: i, level: WordLevel.explorer), isNotNull);
    }
    expect(players.state.canAdd, isFalse);
    expect(await players.add(name: 'Seven', colorIndex: 0, level: WordLevel.explorer), isNull);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await skipHomeIntro();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        definitionServiceProvider.overrideWithValue(_NoDefinitions()),
        wordsOfTheDayProvider.overrideWith((ref) async => _words),
        wordCheckProvider.overrideWithValue((word) async => true),
      ],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('one player alone sees no family screens', (tester) async {
    await pumpApp(tester);
    expect(tester.takeException(), isNull);
    expect(find.text("Who's playing?"), findsNothing);
    expect(find.text('FAMILY WORD'), findsNothing);
    // The Family page only offers to start a family.
    await goToHomePage(tester, 'Family');
    await tester.pumpAndSettle();
    expect(find.text('Play with your family'), findsOneWidget);
    expect(find.text('FAMILY WORD'), findsNothing);
  });

  testWidgets('with two players the app asks who is playing, and Home is theirs', (tester) async {
    SharedPreferences.setMockInitialValues({
      PlayersController.prefsKey: _playersJson([
        ['p1', 'Nana', 0],
        ['p2', 'Leo', 3],
      ]),
      'portfolioData': jsonEncode({'totalXp': 0, 'currency': 5}),
      'p2_portfolioData': jsonEncode({'totalXp': 0, 'currency': 9}),
      'p2_wordLevel': 'sprout',
    });
    await pumpApp(tester);
    expect(tester.takeException(), isNull);
    expect(find.text("Who's playing?"), findsOneWidget);
    expect(find.text('Nana'), findsOneWidget);
    expect(find.text('Leo'), findsOneWidget);

    await tester.tap(find.text('Leo'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text("Who's playing?"), findsNothing);
    expect(find.text('Leo'), findsOneWidget);
    expect(find.text('Sprout'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    await goToHomePage(tester, 'Family');
    await tester.pumpAndSettle();
    expect(find.text('FAMILY WORD'), findsOneWidget);
    expect(find.text('The family'), findsOneWidget);
    expect(find.text('Pass the phone'), findsOneWidget);

    // Switch, and pick the other player: their coins and level.
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(find.text("Who's playing?"), findsOneWidget);
    await tester.tap(find.text('Nana'));
    await tester.pumpAndSettle();
    expect(find.text('Wordsmith'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('9'), findsNothing);
  });

  testWidgets('finishing a Daily finds family letters; a right guess pays everyone', (tester) async {
    SharedPreferences.setMockInitialValues({
      PlayersController.prefsKey: _playersJson([
        ['p1', 'Nana', 0],
        ['p2', 'Leo', 3],
      ], current: 'p2'),
      'p2_wordLevel': 'sprout',
    });
    await pumpApp(tester);
    await tester.tap(find.text('Leo'));
    await tester.pumpAndSettle();
    await goToHomePage(tester, 'Family');
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.text('FAMILY WORD')));
    final now = DateTime.now();
    final familyWord = familyWordFor(now, _words).word;

    // Leo plays his Sprout puzzle from the family word screen.
    await tester.tap(find.text('FAMILY WORD'));
    await tester.pumpAndSettle();
    expect(find.text("Today's family word"), findsOneWidget);
    expect(find.text('Pass to Nana'), findsOneWidget);
    await tester.tap(find.text('Play my puzzle'));
    await _pumpFor(tester, 8);
    final secret = dailyPuzzleFor(now, WordLevel.sprout).secretWord;
    final grid = ProviderScope.containerOf(tester.element(find.byType(GameLayout))).read(gridGameControllerProvider.notifier);
    for (int i = 0; i < secret.length; i++) {
      grid.moveTile(TileLocation(TileZone.rack, grid.state.rackCells.indexOf(secret[i])), TileLocation(TileZone.board, 12 + i));
      await _pumpFor(tester, 2);
    }
    await _pumpFor(tester, 12);
    expect(find.text('You found it!'), findsOneWidget);

    // Half the letters (two players), credited to Leo.
    final family = container.read(familyWordProvider);
    expect(family.found.keys, ['p2']);
    expect(family.found['p2']!.length, (familyWord.length / 2).ceil());
    expect(family.solved, isFalse);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final coinsBefore = container.read(portfolioProvider).currency;

    // Guess it from the family word screen.
    await tester.tap(find.text('FAMILY WORD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('We know it! Guess'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), familyWord.toLowerCase());
    await tester.tap(find.text('Guess'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('You found it together!'), findsOneWidget);
    expect(container.read(portfolioProvider).currency, coinsBefore + kFamilyWordEarlyCoins);
    // Nana's share waits for her.
    expect(container.read(familyWordProvider).owed, {'p1': kFamilyWordEarlyCoins});
    await tester.pump(const Duration(seconds: 5));
  });
}
