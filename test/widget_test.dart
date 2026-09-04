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
}
