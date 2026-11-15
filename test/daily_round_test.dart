// The themed Daily round (spec-05): theme strip, Clue in Swap's place,
// clues that survive leaving, and finding the secret word.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:namer_app/daily/daily_puzzle.dart';
import 'package:namer_app/dictionary/definition_service.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/tile_location.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/screens/daily_challenge_screen.dart';
import 'package:namer_app/ui/game_layout.dart';

class _FakeDefinitions extends DefinitionService {
  _FakeDefinitions(this.meaning);
  final String? meaning;

  @override
  Future<String?> getDefinition(String word) async => meaning;
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
final _puzzle = dailyPuzzleFor(_today);

Finder _oneLetterTexts() => find.byWidgetPredicate(
    (w) => w is Text && w.data != null && w.data!.length == 1 && RegExp(r'^[A-Z]$').hasMatch(w.data!));

Finder _slot(int i) => find.byKey(ValueKey('secret-slot-$i'));

Future<void> _pumpFor(WidgetTester tester, [int times = 4]) async {
  for (int i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _openDaily(WidgetTester tester, {String? meaning}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      definitionServiceProvider.overrideWithValue(_FakeDefinitions(meaning)),
      wordCheckProvider.overrideWithValue((word) async => true),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => DailyChallengeScreen(today: _today))),
            child: const Text('open daily'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open daily'));
  await _pumpFor(tester, 6);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(_loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the round shows the theme, a Clue button, no Swap, and one slot per letter', (tester) async {
    _phone(tester);
    await _openDaily(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(_puzzle.theme.name), findsOneWidget);
    expect(find.text('Clue'), findsOneWidget);
    expect(find.text('3 left'), findsOneWidget);
    expect(find.text('Swap'), findsNothing);
    expect(find.byType(SwapDropTarget), findsNothing);
    expect(find.text('Find the secret word for a bonus.'), findsOneWidget);
    for (int i = 0; i < _puzzle.secretWord.length; i++) {
      expect(_slot(i), findsOneWidget);
    }
    expect(_slot(_puzzle.secretWord.length), findsNothing);
    // The 21 rack letters, and no slot shows a letter yet.
    expect(_oneLetterTexts(), findsNWidgets(21));
  });

  testWidgets('clue 1 shows the first letter, and leaving does not give the clue back', (tester) async {
    _phone(tester);
    await _openDaily(tester);
    final first = _puzzle.secretWord[0];

    await tester.tap(find.text('Clue'));
    await _pumpFor(tester);
    expect(find.text('First letter'), findsOneWidget);
    expect(find.text('It starts with $first.'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await _pumpFor(tester);

    expect(find.descendant(of: _slot(0), matching: find.text(first)), findsOneWidget);
    expect(find.text('2 left'), findsOneWidget);

    await tester.tap(find.byTooltip('Leave round'));
    await _pumpFor(tester);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open daily'));
    await _pumpFor(tester, 6);

    expect(find.text('2 left'), findsOneWidget);
    expect(find.descendant(of: _slot(0), matching: find.text(first)), findsOneWidget);
  });

  testWidgets('clue 2 shows the meaning with the word hidden', (tester) async {
    _phone(tester);
    final secret = _puzzle.secretWord;
    await _openDaily(tester, meaning: 'A ${secret.toLowerCase()} is a thing.');

    await tester.tap(find.text('Clue'));
    await _pumpFor(tester);
    await tester.tap(find.text('Got it'));
    await _pumpFor(tester);
    await tester.tap(find.text('Clue'));
    await _pumpFor(tester);

    expect(find.text('What it means'), findsOneWidget);
    expect(find.text('A this is a thing.'), findsOneWidget);
  });

  testWidgets('clue 2 with no meaning shows the last letter; clue 3 asks first, then shows the word', (tester) async {
    _phone(tester);
    await _openDaily(tester);
    final secret = _puzzle.secretWord;
    final last = secret[secret.length - 1];

    await tester.tap(find.text('Clue'));
    await _pumpFor(tester);
    await tester.tap(find.text('Got it'));
    await _pumpFor(tester);
    await tester.tap(find.text('Clue'));
    await _pumpFor(tester);
    expect(find.text('It ends with $last.'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await _pumpFor(tester);
    expect(find.descendant(of: _slot(secret.length - 1), matching: find.text(last)), findsOneWidget);
    expect(find.text('1 left'), findsOneWidget);

    // "Not yet" keeps the last clue.
    await tester.tap(find.text('Clue'));
    await _pumpFor(tester);
    expect(find.text('Show the whole word?'), findsOneWidget);
    await tester.tap(find.text('Not yet'));
    await _pumpFor(tester);
    expect(find.text('1 left'), findsOneWidget);

    await tester.tap(find.text('Clue'));
    await _pumpFor(tester);
    await tester.tap(find.text('Show it'));
    await _pumpFor(tester);
    expect(find.text("It's $secret. Spell it on the board to earn the bonus."), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await _pumpFor(tester);
    expect(find.text('No more'), findsOneWidget);
    for (int i = 0; i < secret.length; i++) {
      expect(find.descendant(of: _slot(i), matching: find.text(secret[i])), findsOneWidget);
    }
  });

  testWidgets('spelling the secret word fills the strip', (tester) async {
    _phone(tester);
    await _openDaily(tester);
    final secret = _puzzle.secretWord;
    final container = ProviderScope.containerOf(tester.element(find.byType(GameLayout)));
    final controller = container.read(gridGameControllerProvider.notifier);

    for (int i = 0; i < secret.length; i++) {
      expect(find.byIcon(Icons.check_circle), findsNothing);
      final rackIndex = controller.state.rackCells.indexOf(secret[i]);
      controller.moveTile(TileLocation(TileZone.rack, rackIndex), TileLocation(TileZone.board, 20 + i));
      await _pumpFor(tester, 2);
    }

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Found'), findsOneWidget);
    for (int i = 0; i < secret.length; i++) {
      expect(find.descendant(of: _slot(i), matching: find.text(secret[i])), findsOneWidget);
    }
    expect(find.textContaining('Secret word!'), findsOneWidget);
    // Let the banner finish so no animation is left running.
    await _pumpFor(tester, 12);
  });

  testWidgets('at Extra large text on 390x844 all 21 rack tiles are on screen and nothing overflows', (tester) async {
    _phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _openDaily(tester);

    expect(tester.takeException(), isNull);
    const screen = Rect.fromLTWH(0, 0, 390, 844);
    final tiles = _oneLetterTexts();
    expect(tiles, findsNWidgets(21));
    for (final element in tiles.evaluate()) {
      final box = tester.getRect(find.byWidget(element.widget));
      expect(screen.contains(box.topLeft) && screen.contains(box.bottomRight), isTrue);
    }
    expect(find.text('Check words'), findsOneWidget);
  });
}
