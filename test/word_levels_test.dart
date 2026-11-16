// Word levels (spec-06): the four puzzle sizes, the Sprout word lists, and
// the Daily round's rules at Sprout and Explorer.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:namer_app/daily/daily_easy_words.dart';
import 'package:namer_app/daily/daily_puzzle.dart';
import 'package:namer_app/daily/daily_seed.dart';
import 'package:namer_app/daily/daily_themes.dart';
import 'package:namer_app/daily/daily_tier.dart';
import 'package:namer_app/dictionary/definition_service.dart';
import 'package:namer_app/dictionary/word_speaker.dart';
import 'package:namer_app/game/balanced_draw.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/tile_location.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';

import 'home_test_helpers.dart';
import 'package:provider/provider.dart' as provider;
import 'package:namer_app/portfolio/portfolio_controller.dart';
import 'package:namer_app/screens/daily_challenge_screen.dart';
import 'package:namer_app/screens/word_level_screen.dart';
import 'package:namer_app/settings/settings_controller.dart';
import 'package:namer_app/settings/word_level.dart';
import 'package:namer_app/ui/game_layout.dart';
import 'package:namer_app/village/magic_word.dart';

class _NoDefinitions extends DefinitionService {
  @override
  Future<String?> getDefinition(String word) async => null;
}

class _FakeSpeaker extends WordSpeaker {
  final spoken = <String>[];

  @override
  Future<void> speak(String word) async => spoken.add(word);
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

final _today = DateTime.utc(2026, 11, 14, 12);

Finder _slot(int i) => find.byKey(ValueKey('secret-slot-$i'));

Future<void> _pumpFor(WidgetTester tester, [int times = 4]) async {
  for (int i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_FakeSpeaker> _openDaily(WidgetTester tester, WordLevel level) async {
  final speaker = _FakeSpeaker();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      definitionServiceProvider.overrideWithValue(_NoDefinitions()),
      wordCheckProvider.overrideWithValue((word) async => true),
      wordSpeakerProvider.overrideWithValue(speaker),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => DailyChallengeScreen(today: _today, level: level))),
            child: const Text('open daily'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open daily'));
  await _pumpFor(tester, 6);
  return speaker;
}

void main() {
  setUpAll(_loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every theme has 8 Sprout words that follow the list rules', () {
    final dictionary = File('lib_assests/words.txt').readAsLinesSync().map((l) => l.trim().toUpperCase()).toSet();
    expect(kEasyWords.keys.toSet(), {for (final t in kDailyThemes) t.id});
    final all = <String>{};
    for (final entry in kEasyWords.entries) {
      expect(entry.value.length, 8, reason: entry.key);
      for (final easy in entry.value) {
        final word = easy.word;
        expect(RegExp(r'^[A-Z]{3,4}$').hasMatch(word), isTrue, reason: word);
        expect(dictionary.contains(word), isTrue, reason: '$word is not in words.txt');
        expect(magicWordFor(word), isNull, reason: '$word is a magic word');
        expect(all.add(word), isTrue, reason: '$word is listed twice');
        expect(easy.meaning.length, lessThanOrEqualTo(60), reason: word);
        expect(RegExp('\\b$word\\b', caseSensitive: false).hasMatch(easy.meaning), isFalse,
            reason: "$word's meaning uses the word itself");
      }
    }
  });

  test('each level gets the right size of puzzle, every day for 128 days', () {
    for (int d = 0; d < 128; d++) {
      final date = _today.add(Duration(days: d));
      final full = dailyPuzzleFor(date);
      // Wordsmith is exactly the puzzle it was before levels existed.
      expect(full.level, WordLevel.wordsmith);
      expect(full.letters, dailyLettersFor(full.secretWord, dailySeedForDate(date)));

      for (final level in WordLevel.values) {
        final puzzle = dailyPuzzleFor(date, level);
        final info = level.info;
        expect(puzzle.theme.id, full.theme.id);
        expect(puzzle.letters.length, info.letters, reason: '$level day $d');
        // The secret word can be spelled from the letters.
        final pool = [...puzzle.letters];
        for (final l in puzzle.secretWord.split('')) {
          expect(pool.remove(l), isTrue, reason: '${puzzle.secretWord} needs $l ($level day $d)');
        }
        final hard = puzzle.letters.where(kHardLetters.contains).toList();
        expect(hard.toSet().length, hard.length, reason: 'a hard letter twice ($level day $d)');
      }

      final sprout = dailyPuzzleFor(date, WordLevel.sprout);
      expect(sprout.secretWord.length, inInclusiveRange(3, 4));
      expect(sprout.meaning, isNotNull);
      expect(dailyPuzzleFor(date, WordLevel.explorer).secretWord.length, lessThanOrEqualTo(5));
      expect(dailyPuzzleFor(date, WordLevel.builder).secretWord, full.secretWord);
    }
  });

  test('a Sprout always earns the full secret-word coins', () {
    expect(secretWordCoins(4, unlimitedClues: true), 20);
    expect(secretWordCoins(0), 20);
    expect(secretWordCoins(5), 5);
  });

  test('the picked level is saved, and an unset level means Wordsmith', () async {
    final first = SettingsController();
    await first.ready;
    expect(first.state.chosenWordLevel, isNull);
    expect(first.state.wordLevel, WordLevel.wordsmith);
    await first.setWordLevel(WordLevel.explorer);

    final reopened = SettingsController();
    await reopened.ready;
    expect(reopened.state.chosenWordLevel, WordLevel.explorer);
  });

  testWidgets('the level screen saves the level you pick', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: WordLevelScreen())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final level in WordLevel.values) {
      expect(find.text(level.info.name), findsOneWidget);
    }
    expect(find.text('Use Wordsmith'), findsOneWidget);

    await tester.tap(find.text('Sprout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Sprout'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsController.wordLevelKey), 'sprout');
  });

  testWidgets('Sprout: 8 letters, no clock or Check, clues show letters, and the word ends the round', (tester) async {
    _phone(tester);
    final speaker = await _openDaily(tester, WordLevel.sprout);
    final puzzle = dailyPuzzleFor(_today, WordLevel.sprout);
    final secret = puzzle.secretWord;

    expect(tester.takeException(), isNull);
    expect(find.text('Sprout'), findsOneWidget);
    expect(find.text('Check words'), findsNothing);
    expect(find.text('Give up'), findsNothing);
    expect(find.text('Next letter'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(GameLayout)));
    final controller = container.read(gridGameControllerProvider.notifier);
    expect(controller.state.rackCells.where((c) => c != null).length, 8);
    expect(controller.state.boardCells.length, 36);

    // Each clue shows the next letter, with no dialog in the way.
    await tester.tap(find.text('Clue'));
    await _pumpFor(tester, 2);
    expect(find.descendant(of: _slot(0), matching: find.text(secret[0])), findsOneWidget);
    await tester.tap(find.text('Clue'));
    await _pumpFor(tester, 2);
    expect(find.descendant(of: _slot(1), matching: find.text(secret[1])), findsOneWidget);

    for (int i = 0; i < secret.length; i++) {
      final rackIndex = controller.state.rackCells.indexOf(secret[i]);
      controller.moveTile(TileLocation(TileZone.rack, rackIndex), TileLocation(TileZone.board, 12 + i));
      await _pumpFor(tester, 2);
    }
    await _pumpFor(tester, 12);

    expect(tester.takeException(), isNull);
    expect(find.text('You found it!'), findsOneWidget);
    expect(find.text(puzzle.meaning!), findsOneWidget);
    expect(find.text('+20 coins'), findsOneWidget);
    expect(container.read(portfolioProvider).currency, 20);

    await tester.tap(find.text('Hear the word'));
    await _pumpFor(tester, 2);
    expect(speaker.spoken, [secret]);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('open daily'), findsOneWidget);
  });

  testWidgets('Explorer: 5 clues, no clock, and it finishes with 2 letters left over', (tester) async {
    _phone(tester);
    await _openDaily(tester, WordLevel.explorer);

    expect(tester.takeException(), isNull);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('5 left'), findsOneWidget);
    expect(find.text('You can finish with 2 letters left over.'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(GameLayout)));
    final controller = container.read(gridGameControllerProvider.notifier);
    expect(controller.state.rackCells.where((c) => c != null).length, 12);
    expect(controller.state.boardCells.length, 64);

    // The first two clues: first letter, then last letter.
    final secret = dailyPuzzleFor(_today, WordLevel.explorer).secretWord;
    await tester.tap(find.text('Clue'));
    await _pumpFor(tester);
    expect(find.text('It starts with ${secret[0]}.'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await _pumpFor(tester);
    await tester.tap(find.text('Clue'));
    await _pumpFor(tester);
    expect(find.text('It ends with ${secret[secret.length - 1]}.'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await _pumpFor(tester);
    expect(find.text('3 left'), findsOneWidget);
    expect(find.descendant(of: _slot(secret.length - 1), matching: find.text(secret[secret.length - 1])),
        findsOneWidget);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    _phone(tester);
    await skipHomeIntro();
    await tester.pumpWidget(ProviderScope(
      overrides: [definitionServiceProvider.overrideWithValue(_NoDefinitions())],
      child: provider.ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> leaveRound(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Leave round'));
    await _pumpFor(tester);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
  }

  testWidgets('a new player picks a level before their first Daily, and Home then shows it', (tester) async {
    await pumpApp(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Wordsmith'), findsOneWidget);

    await tester.tap(find.text('Daily puzzle'));
    await tester.pumpAndSettle();
    expect(find.text('Your word level'), findsOneWidget);
    await tester.tap(find.text('Sprout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Sprout'));
    await _pumpFor(tester, 8);
    expect(find.text('Sprout'), findsOneWidget);

    await leaveRound(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Sprout'), findsOneWidget);
    expect(find.text('Wordsmith'), findsNothing);

    // The second time there is no picker.
    await tester.tap(find.text('Daily puzzle'));
    await _pumpFor(tester, 8);
    expect(find.text('Your word level'), findsNothing);
    expect(find.text('Sprout'), findsOneWidget);
    await leaveRound(tester);
  });

  testWidgets('a saved level opens its own puzzle straight away', (tester) async {
    SharedPreferences.setMockInitialValues({SettingsController.wordLevelKey: 'explorer'});
    await pumpApp(tester);
    expect(find.text('Explorer'), findsOneWidget);

    await tester.tap(find.text('Daily puzzle'));
    await _pumpFor(tester, 8);
    expect(find.text('Your word level'), findsNothing);
    expect(find.text('Explorer'), findsOneWidget);
    await leaveRound(tester);
  });

  test('Check wins once few enough letters are left', () {
    DailyCheck check(bool ok, int left, int allowed) =>
        dailyCheckOutcome(boardOk: ok, lettersLeft: left, leftoverAllowed: allowed);
    // Explorer: 2 may be left over.
    expect(check(true, 2, 2), DailyCheck.win);
    expect(check(true, 0, 2), DailyCheck.win);
    expect(check(true, 3, 2), DailyCheck.placeMore);
    expect(check(false, 0, 2), DailyCheck.notYet);
    // Builder and Wordsmith: every letter.
    expect(check(true, 0, 0), DailyCheck.win);
    expect(check(true, 1, 0), DailyCheck.notYet);
  });
}
