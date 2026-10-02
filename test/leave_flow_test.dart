import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/daily_challenge_controller.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/screens/daily_challenge_screen.dart';
import 'package:namer_app/ui/game_layout.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Timed screens never settle, so pump in bounded steps.
Future<void> pumpFor(WidgetTester tester, {int frames = 10}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> startTimeAttack(WidgetTester tester) async {
    phoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Time Attack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start - 3:00'));
    await pumpFor(tester);
    expect(find.text('Time left'), findsOneWidget);
  }

  testWidgets('Leave asks first; Keep playing stays, Leave goes Home', (tester) async {
    await startTimeAttack(tester);

    // The timer pill fills the bar rather than a fixed third of it.
    final barWidth = tester.getSize(find.byType(Scaffold)).width;
    expect(tester.getSize(find.byType(GamePill)).width, greaterThan(barWidth * 0.45));

    await tester.tap(find.byTooltip('Leave round'));
    await pumpFor(tester);
    expect(find.text('Leave this round?'), findsOneWidget);

    await tester.tap(find.text('Keep playing'));
    await pumpFor(tester);
    expect(find.text('Leave this round?'), findsNothing);
    expect(find.text('Time left'), findsOneWidget);

    await tester.tap(find.byTooltip('Leave round'));
    await pumpFor(tester);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Visit your village'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the back gesture opens the same Leave dialog', (tester) async {
    await startTimeAttack(tester);

    await tester.binding.handlePopRoute();
    await pumpFor(tester);
    expect(find.text('Leave this round?'), findsOneWidget);
    expect(find.text('Swipe again to exit'), findsNothing);

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Visit your village'), findsOneWidget);
  });

  testWidgets("leaving the Daily doesn't record an attempt", (tester) async {
    phoneSize(tester);
    Future<String> tinyDictionary() async => 'cat\ndog\nrat\nsun\n';
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DailyChallengeScreen(dictionaryLoader: tinyDictionary)),
              ),
              child: const Text('open daily'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open daily'));
    for (int i = 0; i < 60 && find.text('Check words').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.tap(find.byTooltip('Leave round'));
    await pumpFor(tester);
    expect(find.text("Leave today's puzzle?"), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();

    expect(find.text('open daily'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.text('open daily')));
    expect(container.read(dailyChallengeProvider.notifier).hasPlayedToday(DateTime.now()), isFalse);
  });

  testWidgets('the Daily top bar fits a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(720, 1520);
    tester.view.devicePixelRatio = 2.0; // 360 x 760 logical
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Future<String> tinyDictionary() async => 'cat\n';
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: DailyChallengeScreen(dictionaryLoader: tinyDictionary)),
    ));
    for (int i = 0; i < 60 && find.text('Check words').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Give up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
