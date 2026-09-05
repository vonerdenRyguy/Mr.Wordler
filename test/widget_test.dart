// Basic smoke tests: the app boots, and navigating into each built mode
// renders without error.

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
// setup the real app runs with -- ModeSelectScreen/PortfolioScreen read
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

void main() {
  // PortfolioController reads SharedPreferences as soon as it's created
  // (unlike ThemeNotifier, whose loadFromPrefs() these tests never call);
  // without a mock, SharedPreferences.getInstance() throws in the test
  // environment.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Menu screen shows title and buttons', (WidgetTester tester) async {
    await pumpApp(tester);

    expect(find.text('Mr. Wordler'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
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

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    // A build-time exception in one subtree (e.g. GridBoardView) doesn't
    // fail pumpAndSettle by itself -- Flutter swaps just that subtree for
    // a red ErrorWidget and keeps going, which let a real Riverpod scoping
    // bug here slip past this test once already. Assert both explicitly:
    // no exception was recorded, and no error widget is anywhere in the tree.
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);

    expect(find.text('Check'), findsOneWidget);
    // 21 letters should have been dealt into the rack -- confirms the
    // Riverpod-backed GridGameController actually initialized and dealt
    // tiles rather than throwing during setup.
    expect(oneLetterTileFinder(), findsNWidgets(21));
  });

  testWidgets('Game Modes: swiping changes page and shows each explanation',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await tester.tap(find.text('Game Modes'));
    await tester.pumpAndSettle();

    // Starts on Daily Estate Challenge, with its explanation and Play button.
    expect(find.text('Daily Estate Challenge'), findsOneWidget);
    expect(find.text('Play Daily Estate Challenge'), findsOneWidget);

    // Swiping left should move to the next page (Time Attack) without
    // needing to tap the bottom nav bar.
    await tester.fling(find.text('Daily Estate Challenge').first, const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Play Time Attack'), findsOneWidget);
  });

  testWidgets('Time Attack mode deals a rack via the shared grid engine', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await tester.tap(find.text('Game Modes'));
    await tester.pumpAndSettle();
    // "Time Attack" is unambiguous here: the default page (Daily Estate
    // Challenge) doesn't show that text yet, only the bottom nav item does.
    expect(find.text('Time Attack'), findsOneWidget);
    await tester.tap(find.text('Time Attack'));
    await tester.pumpAndSettle();

    // Now on the Time Attack detail page -- "Time Attack" matches both the
    // bottom nav item and the page title, so target the unique Play button.
    expect(find.text('Play Time Attack'), findsOneWidget);
    await tester.tap(find.text('Play Time Attack'));
    await tester.pumpAndSettle();

    // Same explicit checks as the Free Play test -- see the comment there
    // for why a plain widget count alone isn't enough to catch a broken
    // subtree.
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);

    expect(find.text('Check'), findsOneWidget);
    expect(oneLetterTileFinder(), findsNWidgets(21));
  });

  testWidgets('Portfolio screen shows neighborhoods and test controls work', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await tester.tap(find.text('Game Modes'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);

    await tester.tap(find.byTooltip('Portfolio'));
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

    await tester.tap(find.text('+10 coins'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    // The currency display should now read 10 instead of 0.
    expect(find.text('10'), findsOneWidget);
    expect(find.text('0'), findsNothing);
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
    // of the full app/menu, since ModeSelectScreen's navigation always
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
    await pumpUntilFound(tester, find.text('Check'));

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Check'), findsOneWidget);
    expect(find.text('Give Up'), findsOneWidget);
    expect(oneLetterTileFinder(), findsNWidgets(21));

    await tester.tap(find.text('Give Up'));
    await pumpUntilFound(tester, find.text('Keep Playing'));
    // Confirm the "you'll lose today's attempt" dialog.
    await tester.tap(find.text('Give Up').last);
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

    await tester.tap(find.text('Game Modes'));
    await tester.pumpAndSettle();
    // Unambiguous here: the default page doesn't show "Theme Rush" yet.
    await tester.tap(find.text('Theme Rush'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play Theme Rush'));
    // No perpetual timer yet -- it only starts after tapping Start.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text("Today's theme:"), findsOneWidget);
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

    await tester.tap(find.text('Game Modes'));
    await tester.pumpAndSettle();
    // Bottom nav label is the short "Infinite"; the page itself says
    // "Infinite Estate".
    await tester.tap(find.text('Infinite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play Infinite Estate'));
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
    expect(find.text('End Session'), findsOneWidget);
    expect(oneLetterTileFinder(), findsNWidgets(21));

    // Structure abilities (Well/Bridge) only appear once their magic word
    // is actually built -- a fresh board has none, so neither should show.
    expect(find.text('Draw from Well'), findsNothing);
    expect(find.byTooltip('Jump to Landmark'), findsNothing);

    // Switching to Village view should render without error. A fresh
    // board has no magic words built yet, so Words view's 21 rack tiles
    // are still there (the rack is unaffected by the toggle) but the
    // board itself shows no letters in Village view.
    expect(find.text('Words'), findsOneWidget);
    expect(find.text('Village'), findsOneWidget);
    await tester.tap(find.text('Village'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    // The rack (unaffected by the toggle) still shows its 21 letters;
    // the empty board itself contributes none in Village view.
    expect(oneLetterTileFinder(), findsNWidgets(21));

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
    await tester.tap(find.byTooltip('Discovery Journal'));
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
    // narrower phone width and a larger text scale, both of which make
    // that row wider relative to the toolbar than the default test size
    // does.
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester);

    await tester.tap(find.text('Game Modes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Infinite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play Infinite Estate'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byIcon(Icons.landscape), findsOneWidget);
    expect(find.text('End Session'), findsOneWidget);
  });

  testWidgets('Stats screen shows all sections', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await tester.tap(find.text('Game Modes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stats'));
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
