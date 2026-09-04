// Basic smoke test: the app boots and the menu screen shows up with
// its title and both action buttons.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';

void main() {
  testWidgets('Menu screen shows title and buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeNotifier(),
        child: const MyApp(),
      ),
    );

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

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeNotifier(),
        child: const MyApp(),
      ),
    );

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
    final letterFinder = find.byWidgetPredicate((widget) =>
        widget is Text &&
        widget.data != null &&
        widget.data!.length == 1 &&
        RegExp(r'^[A-Z]$').hasMatch(widget.data!));
    expect(letterFinder, findsNWidgets(21));
  });

  testWidgets('Time Attack mode deals a rack via the shared grid engine', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeNotifier(),
        child: const MyApp(),
      ),
    );

    await tester.tap(find.text('Game Modes'));
    await tester.pumpAndSettle();
    expect(find.text('Time Attack'), findsOneWidget);

    await tester.tap(find.text('Time Attack'));
    await tester.pumpAndSettle();

    // Same explicit checks as the Free Play test -- see the comment there
    // for why a plain widget count alone isn't enough to catch a broken
    // subtree.
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);

    expect(find.text('Check'), findsOneWidget);
    final letterFinder = find.byWidgetPredicate((widget) =>
        widget is Text &&
        widget.data != null &&
        widget.data!.length == 1 &&
        RegExp(r'^[A-Z]$').hasMatch(widget.data!));
    expect(letterFinder, findsNWidgets(21));
  });
}
