// Basic smoke tests: the app boots, and navigating into each built mode
// renders without error.

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
import 'package:namer_app/main.dart';
import 'package:namer_app/screens/daily_challenge_screen.dart';
import 'package:namer_app/util/theme_notifier.dart';

import 'home_test_helpers.dart';

// Mirrors main()'s actual widget nesting (ProviderScope wraps
// ChangeNotifierProvider wraps MyApp) so tests exercise the same provider
// setup the real app runs with -- HomeScreen/PortfolioScreen read
// the global portfolioProvider directly and need an ancestor ProviderScope
// to do that, the same as they would in production.
Future<void> pumpApp(WidgetTester tester) async {
  await skipHomeIntro();
  await tester.pumpWidget(
    ProviderScope(
      child: ChangeNotifierProvider(
        create: (_) => ThemeNotifier(),
        child: const MyApp(),
      ),
    ),
  );
}

// Screens with a perpetual Timer.periodic (a running stopwatch/countdown)
// never fully "settle" -- pumpAndSettle is documented as unsuitable for
// that and can time out waiting for a quiet frame that never comes. Pump
// a bounded number of times instead, stopping as soon as `finder` appears.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder,
    {int maxTries = 60, Duration step = const Duration(milliseconds: 300)}) async {
  for (int i = 0; i < maxTries && finder.evaluate().isEmpty; i++) {
    await tester.pump(step);
  }
}

Finder oneLetterTileFinder() => find.byWidgetPredicate((widget) =>
    widget is Text &&
    widget.data != null &&
    widget.data!.length == 1 &&
    RegExp(r'^[A-Z]$').hasMatch(widget.data!));

// How each mode is reached from Home. Kept in one place so the tests
// follow the app's navigation as it changes.
Future<void> openTimeAttack(WidgetTester tester) async {
  await tester.tap(find.text('Time Attack'));
  await tester.pumpAndSettle();
  expect(find.text('Use every letter before the clock runs out.'), findsOneWidget);
  await tester.tap(find.text('Start - 3:00'));
  await tester.pumpAndSettle();
}

// Tests draw text in a placeholder font with wide square glyphs, which
// wraps text the real fonts don't. Layout-size checks load the real ones.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('LilitaOne', ['assets/fonts/LilitaOne-Regular.ttf']);
  await load('Atkinson', ['assets/fonts/AtkinsonHyperlegible-Regular.ttf', 'assets/fonts/AtkinsonHyperlegible-Bold.ttf']);
}

void main() {
  setUpAll(loadAppFonts);

  // PortfolioController reads SharedPreferences as soon as it's created
  // (unlike ThemeNotifier, whose loadFromPrefs() these tests never call);
  // without a mock, SharedPreferences.getInstance() throws in the test
  // environment.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home: Play, Me and Family each fit one screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.pumpAndSettle();

    const screen = Rect.fromLTWH(0, 0, 390, 844);
    void onScreen(List<String> labels) {
      for (final label in labels) {
        expect(find.text(label), findsOneWidget, reason: label);
        final box = tester.getRect(find.text(label));
        expect(screen.contains(box.topLeft) && screen.contains(box.bottomRight), isTrue,
            reason: '$label is fully on screen without scrolling');
      }
    }

    // Play opens first: the village, the Daily and Time Attack.
    expect(tester.takeException(), isNull);
    final theme = 'Theme: ${dailyPuzzleFor(DateTime.now()).theme.name}';
    onScreen(['Visit your village', 'Daily puzzle', 'Time Attack', 'New village', theme, 'Me', 'Family']);
    // "Play" is the tab and both games' buttons.
    expect(screen.contains(tester.getRect(find.text('Play').last).bottomRight), isTrue);
    expect(find.text('Free Play'), findsNothing);
    expect(find.text('Theme Rush'), findsNothing);
    // No "0-day streak".
    expect(find.textContaining('streak'), findsNothing);
    // No scroll bar anywhere.
    expect(find.byType(Scrollbar), findsNothing);

    // Me: today's word with its reward chip, and four squares.
    final words = parseWordsOfTheDay(File('assets/words/word_of_the_day.json').readAsStringSync());
    final today = wordOfDayFor(DateTime.now(), words);
    await goToHomePage(tester, 'Me');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    onScreen(['WORD OF THE DAY', today.word, '+10 coins', 'Word journal', 'My properties', 'My stats', 'Word level']);

    // Family, with no family yet: two ways to start one.
    await goToHomePage(tester, 'Family');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    onScreen(['Play with your family', 'On this phone', 'On different phones']);
  });

  testWidgets('tapping the Word of the day card opens its sheet', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.pumpAndSettle();

    final words = parseWordsOfTheDay(File('assets/words/word_of_the_day.json').readAsStringSync());
    final today = wordOfDayFor(DateTime.now(), words);
    await goToHomePage(tester, 'Me');
    await tester.tap(find.text('WORD OF THE DAY'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Word of the day'), findsOneWidget);
    // On the card (one line) and, in full, in the sheet.
    expect(find.text(today.meaning), findsNWidgets(2));
    expect(find.text('Spell it in your village today for +10 coins.'), findsOneWidget);
    expect(find.bySemanticsLabel(today.word), findsOneWidget);
  });

  testWidgets('Time Attack mode deals a rack via the shared grid engine', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await openTimeAttack(tester);

    // A build-time exception in one subtree doesn't fail pumpAndSettle by
    // itself -- Flutter swaps just that subtree for a red ErrorWidget and
    // keeps going. Assert both explicitly.
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);

    expect(find.text('Check words'), findsOneWidget);
    expect(oneLetterTileFinder(), findsNWidgets(21));
  });

  testWidgets('Portfolio screen shows neighborhoods and no test controls', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await goToHomePage(tester, 'Me');
    await tester.tap(find.text('My properties'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Level 1'), findsOneWidget);
    for (final name in ['Ocean Ave', 'Downtown', 'Old Town']) {
      expect(find.text(name), findsOneWidget);
    }

    // The tier guide explains how each property tier is earned (rendered
    // as RichText/TextSpan -- find.text needs findRichText: true for that,
    // and matches against the whole span's concatenated text, so use
    // textContaining rather than an exact match against just the label).
    expect(find.text('How Properties Work'), findsOneWidget);
    expect(find.textContaining('Vacant Lot', findRichText: true), findsOneWidget);
    expect(find.textContaining('Cottage', findRichText: true), findsOneWidget);
    expect(find.textContaining('House', findRichText: true), findsOneWidget);
    expect(find.textContaining('Mansion', findRichText: true), findsOneWidget);

    // A fresh portfolio has every slot empty, grayed out with a lock.
    expect(find.text('Empty'), findsNWidgets(9)); // 3 neighborhoods x 3 slots
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
    expect(find.text('Perk (locked)'), findsNWidgets(3));

    // A fresh portfolio starts at 0 coins.
    expect(find.text('0'), findsOneWidget);

    // The temporary dev-only test controls are gone.
    expect(find.textContaining('Test controls'), findsNothing);
    expect(find.text('+10 coins'), findsNothing);
  });

  testWidgets('Daily Challenge deals a rack, and giving up locks today out',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A minimal two-route harness (root screen -> Daily puzzle) instead of
    // the full app, so the test can come back and reopen it.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DailyChallengeScreen(),
                  ),
                ),
                child: const Text('open daily'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open daily'));
    // Reaching the ready state starts a perpetual stopwatch, so wait for
    // it with bounded pumps instead of pumpAndSettle (see pumpUntilFound).
    await pumpUntilFound(tester, find.text('Check words'));

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Check words'), findsOneWidget);
    expect(find.text('Give up'), findsOneWidget);
    expect(oneLetterTileFinder(), findsNWidgets(21));

    await tester.tap(find.text('Give up'));
    await pumpUntilFound(tester, find.text('Keep Playing'));
    // Confirm the "you'll lose today's attempt" dialog.
    await tester.tap(find.text('Give Up'));
    // This pop leaves the screen with the perpetual stopwatch, so
    // pumpAndSettle is safe again from here on.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    // Giving up pops back to the root screen.
    expect(find.text('open daily'), findsOneWidget);

    // Reopening today should now show the locked-out view, not a fresh board.
    await tester.tap(find.text('open daily'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text("You've already played today!"), findsOneWidget);
    // The title is "Daily puzzle" and fits (no "..." cut-off).
    final title = tester.widget<Text>(find.text('Daily puzzle'));
    expect(title.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.getRect(find.text('Daily puzzle')).right, lessThanOrEqualTo(1080));
    expect(find.textContaining('gave up'), findsOneWidget);

    // The share button should copy a result summary without throwing.
    await tester.tap(find.text('Share Result'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Result copied to clipboard!'), findsOneWidget);
  });

  testWidgets('Infinite Estate deals a rack on a larger board', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await tester.tap(find.text('Visit your village'));
    // No perpetual timer in this mode -- pumpAndSettle is safe throughout.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    // Tapping the score chip itself re-checks the score (there's no
    // separate "Score" button).
    expect(find.byIcon(Icons.landscape), findsOneWidget);
    await tester.tap(find.byIcon(Icons.landscape));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('End'), findsOneWidget);
    expect(oneLetterTileFinder(), findsNWidgets(10));

    // Structure abilities (Well/Bridge) only appear once their magic word
    // is actually built -- a fresh board has none, so neither should show.
    expect(find.text('Free letter'), findsNothing);
    expect(find.text('Jump'), findsNothing);

    // Switching to Village view should render without error. You can't
    // place letters there, so the rack is hidden, and a fresh village
    // shows the first-building helper instead.
    expect(find.text('Words'), findsOneWidget);
    expect(find.text('Village'), findsOneWidget);
    await tester.tap(find.text('Village'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Build your first building'), findsOneWidget);
    expect(find.text('Go to Words'), findsOneWidget);
    expect(find.text('Swap'), findsNothing);

    // Switching back to Words view should restore the interactive board.
    await tester.tap(find.text('Words'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);

    // Long-pressing a rack tile should pin it (a UI-only marker).
    expect(find.byIcon(Icons.push_pin), findsNothing);
    await tester.longPress(oneLetterTileFinder().first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    // The Discovery Journal should open and list the magic word catalog.
    await tester.tap(find.text('Journal 0/8'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Discovery Journal'), findsOneWidget);
    expect(find.text('Well'), findsOneWidget);
    expect(find.text('Farm'), findsOneWidget);
    expect(find.text('Bridge'), findsOneWidget);
  });

  testWidgets('Infinite Estate AppBar does not overflow on a narrow screen with larger system text',
      (WidgetTester tester) async {
    // Regression test: the AppBar's Score/score-chip/End Session row
    // previously overflowed by a few pixels once the Discovery Journal
    // action icon ate into its available width -- reproduced with a
    // narrower phone width and a larger text scale. The score, Journal
    // and abilities now live in their own wrapping row under the AppBar,
    // but the same narrow/large-text setup still guards against overflow.
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester);

    await tester.tap(find.text('Visit your village'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byIcon(Icons.landscape), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
  });

  Future<void> openInfiniteEstate(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.tap(find.text('Visit your village'));
    await tester.pumpAndSettle();
  }

  testWidgets('Infinite Estate shows 10 rack tiles in 2 rows and a Swap button beside the rack', (WidgetTester tester) async {
    await openInfiniteEstate(tester);

    expect(tester.takeException(), isNull);
    final tiles = oneLetterTileFinder().evaluate().toList();
    expect(tiles.length, 10);
    final rows = tiles.map((e) => tester.getCenter(find.byWidget(e.widget)).dy.round()).toSet();
    expect(rows.length, 2);
    expect(find.text('Swap'), findsOneWidget);
  });

  testWidgets('the first Swap is free; then with 0 coins it says "Need 5 coins" and does nothing',
      (WidgetTester tester) async {
    await openInfiniteEstate(tester);

    expect(find.text('Free'), findsOneWidget);
    await tester.tap(find.text('Swap'));
    await tester.pumpAndSettle();

    expect(find.text('Need 5 coins'), findsOneWidget);
    String rackLetters() => oneLetterTileFinder().evaluate().map((e) => (e.widget as Text).data).join();
    final before = rackLetters();
    await tester.tap(find.text('Swap'));
    await tester.pumpAndSettle();
    expect(rackLetters(), before);
  });

  testWidgets('a version-1 village save opens with 10 rack tiles and the same board', (WidgetTester tester) async {
    const size = 500;
    const center = (size ~/ 2) * size + size ~/ 2;
    final board = List<String?>.filled(size * size, null);
    board[center] = 'W';
    board[center + 1] = 'E';
    board[center + 2] = 'L';
    board[center + 3] = 'L';
    final rack = [for (int i = 0; i < 21; i++) 'ABCDEFGHIJKLMNOPRSTUV'[i]];
    SharedPreferences.setMockInitialValues({
      'infiniteEstateVillageSave': jsonEncode({
        'boardCells': board,
        'rackCells': rack,
        'pool': List<String>.filled(50, 'E'),
        'dealtLetters': ['W', 'E', 'L', 'L', ...rack],
        'lastCashedOutScore': 0,
      }),
    });

    await openInfiniteEstate(tester);

    expect(tester.takeException(), isNull);
    // 4 board letters around the center (where the view opens) + 10 rack.
    expect(oneLetterTileFinder(), findsNWidgets(14));
    for (final l in ['W', 'L']) {
      expect(find.text(l), findsWidgets);
    }
    final rackTexts = oneLetterTileFinder().evaluate().map((e) => (e.widget as Text).data).toList();
    expect(rackTexts, containsAll(['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J']));
    expect(rackTexts, isNot(contains('K')));
  });

  testWidgets('Infinite Estate at Extra large text on 390x844: the whole rack shows, nothing overflows',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'textSizeStep': 2});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Visit your village'));
    await tester.tap(find.text('Visit your village'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final tiles = oneLetterTileFinder().evaluate().toList();
    expect(tiles.length, 10);
    const screen = Rect.fromLTWH(0, 0, 390, 844);
    for (final t in tiles) {
      final r = tester.getRect(find.byWidget(t.widget));
      expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight), isTrue);
    }
  });

  testWidgets('Stats screen shows all sections', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await goToHomePage(tester, 'Me');
    await tester.tap(find.text('My stats'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Overall'), findsOneWidget);
    expect(find.text('Daily puzzle'), findsOneWidget);
    expect(find.text('Infinite Estate'), findsOneWidget);
    expect(find.text('Theme Rush (best times)'), findsNothing);
    expect(find.text('Free Play top times'), findsNothing);
  });
}
