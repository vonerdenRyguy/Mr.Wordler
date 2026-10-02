// Basic smoke tests: the app boots, and navigating into each built mode
// renders without error.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:namer_app/main.dart';
import 'package:namer_app/screens/daily_challenge_screen.dart';
import 'package:namer_app/util/theme_notifier.dart';

// Mirrors main()'s actual widget nesting (ProviderScope wraps
// ChangeNotifierProvider wraps MyApp) so tests exercise the same provider
// setup the real app runs with -- HomeScreen/PortfolioScreen read
// the global portfolioProvider directly and need an ancestor ProviderScope
// to do that, the same as they would in production.
Future<void> pumpApp(WidgetTester tester) async {
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
Future<void> openFreePlay(WidgetTester tester) async {
  await tester.tap(find.text('Free Play'));
  await tester.pumpAndSettle();
  expect(find.text('Build words at your own pace.'), findsOneWidget);
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
}

Future<void> openTimeAttack(WidgetTester tester) async {
  await tester.tap(find.text('Time Attack'));
  await tester.pumpAndSettle();
  expect(find.text('Use every letter before the clock runs out.'), findsOneWidget);
  await tester.tap(find.text('Start - 3:00'));
  await tester.pumpAndSettle();
}

Future<void> openThemeRush(WidgetTester tester) async {
  await tester.tap(find.text('Theme Rush'));
}

void main() {
  // PortfolioController reads SharedPreferences as soon as it's created
  // (unlike ThemeNotifier, whose loadFromPrefs() these tests never call);
  // without a mock, SharedPreferences.getInstance() throws in the test
  // environment.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home shows village, daily, and modes', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Mr. Wordler'), findsOneWidget);
    for (final label in ['Visit your village', "Today's puzzle", 'Free Play', 'Time Attack', 'Theme Rush']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Leaderboard'), findsNothing);
    expect(find.text('New village'), findsOneWidget);
  });

  testWidgets('Game screen deals a rack via the shared grid engine', (WidgetTester tester) async {
    // The default 800x600 test surface doesn't give the rack's GridView
    // enough height to lay out all 3 rows (it lazily builds only what's
    // visible, same as on a real device) -- use a phone-sized surface so
    // the whole rack actually renders.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await openFreePlay(tester);

    // A build-time exception in one subtree (e.g. GridBoardView) doesn't
    // fail pumpAndSettle by itself -- Flutter swaps just that subtree for
    // a red ErrorWidget and keeps going, which let a real Riverpod scoping
    // bug here slip past this test once already. Assert both explicitly:
    // no exception was recorded, and no error widget is anywhere in the tree.
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);

    expect(find.text('Check words'), findsOneWidget);
    // 21 letters should have been dealt into the rack -- confirms the
    // Riverpod-backed GridGameController actually initialized and dealt
    // tiles rather than throwing during setup.
    expect(oneLetterTileFinder(), findsNWidgets(21));
  });

  testWidgets('Time Attack mode deals a rack via the shared grid engine', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await openTimeAttack(tester);

    // Same explicit checks as the Free Play test -- see the comment there
    // for why a plain widget count alone isn't enough to catch a broken
    // subtree.
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

    await tester.tap(find.text('Portfolio'));
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

    // A small stand-in dictionary, injected via DailyChallengeScreen's
    // test-only dictionaryLoader. The real ~1.5MB words.txt can't be used
    // here: flutter_test's mocked asset channel hangs on messages roughly
    // above 45-90KB (verified directly; not a production issue -- see
    // pickBonusWord's doc comment). Whether this list happens to contain a
    // word formable from today's actual dealt letters doesn't matter for
    // this test; a null bonus word is a normal, handled case.
    Future<String> tinyDictionary() async => 'cat\ndog\nrat\nsun\nrun\ntree\nstar\nrose\nnote\ngate\n';

    // A minimal two-route harness (root screen -> Daily Challenge) instead
    // of the full app, since Home's navigation always
    // constructs a real DailyChallengeScreen with no way to inject the
    // test dictionary loader from outside.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DailyChallengeScreen(dictionaryLoader: tinyDictionary),
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
    expect(find.textContaining('gave up'), findsOneWidget);

    // The share button should copy a result summary without throwing.
    await tester.tap(find.text('Share Result'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Result copied to clipboard!'), findsOneWidget);
  });

  testWidgets('Theme Rush shows a theme, then deals a rack once started',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await openThemeRush(tester);
    // No perpetual timer yet -- it only starts after tapping Start.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Spell one word that fits the theme.'), findsOneWidget);
    expect(find.textContaining('Theme: '), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Start'));
    // Starting begins a perpetual stopwatch, so wait with bounded pumps.
    await pumpUntilFound(tester, oneLetterTileFinder());

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(oneLetterTileFinder(), findsNWidgets(21));
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

    // Switching to Village view should render without error. A fresh
    // board has no magic words built yet, so Words view's 10 rack tiles
    // are still there (the rack is unaffected by the toggle) but the
    // board itself shows no letters in Village view.
    expect(find.text('Words'), findsOneWidget);
    expect(find.text('Village'), findsOneWidget);
    await tester.tap(find.text('Village'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    // The rack (unaffected by the toggle) still shows its 10 letters;
    // the empty board itself contributes none in Village view.
    expect(oneLetterTileFinder(), findsNWidgets(10));

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

  testWidgets('Infinite Estate shows 10 rack tiles in 2 rows and a Swap button', (WidgetTester tester) async {
    await openInfiniteEstate(tester);

    expect(tester.takeException(), isNull);
    final tiles = oneLetterTileFinder().evaluate().toList();
    expect(tiles.length, 10);
    final rows = tiles.map((e) => tester.getCenter(find.byWidget(e.widget)).dy.round()).toSet();
    expect(rows.length, 2);
    expect(find.text('Swap letters'), findsOneWidget);
  });

  testWidgets('Swap with 0 coins says "Need 5 coins" and does nothing', (WidgetTester tester) async {
    await openInfiniteEstate(tester);

    expect(find.text('Need 5 coins'), findsOneWidget);
    String rackLetters() => oneLetterTileFinder().evaluate().map((e) => (e.widget as Text).data).join();
    final before = rackLetters();
    await tester.tap(find.text('Swap letters'));
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

  testWidgets('Stats screen shows all sections', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Overall'), findsOneWidget);
    expect(find.text('Daily Estate Challenge'), findsOneWidget);
    expect(find.text('Theme Rush (best times)'), findsOneWidget);
    expect(find.text('Infinite Estate'), findsOneWidget);
    for (final name in ['Animals', 'Food', 'Countries']) {
      expect(find.text(name), findsOneWidget);
    }
  });
}
