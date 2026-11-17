// Reward moments (spec-12): a card, Collect, coins fly into the counter.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/portfolio/portfolio_controller.dart';
import 'package:namer_app/sound/sound_service.dart';
import 'package:namer_app/ui/reward_moment.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sound_test.dart' show FakeSoundBackend;

void main() {
  Future<FakeSoundBackend> open(WidgetTester tester,
      {bool reduceMotion = false, String? ribbon, String button = 'Collect', int coins = 10}) async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeSoundBackend();
    await tester.pumpWidget(ProviderScope(
      overrides: [soundBackendProvider.overrideWithValue(fake)],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await ref.read(portfolioProvider.notifier).ready;
                  ref.read(portfolioProvider.notifier).addCurrency(coins);
                  if (!context.mounted) return;
                  showRewardMoment(context,
                      title: 'Well done!', word: 'horse', coins: coins, ribbon: ribbon, buttonLabel: button);
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('Collect flies the coins into the counter, which counts up, then closes', (tester) async {
    final fake = await open(tester);
    expect(find.text('Well done!'), findsOneWidget);
    expect(find.text('HORSE'), findsOneWidget);
    expect(find.text('+10'), findsOneWidget);
    expect(find.text('0'), findsOneWidget); // the counter, before Collect
    expect(fake.sfx, [Sfx.reward]);

    await tester.tap(find.text('Collect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Mid-flight: some coins are in the air.
    expect(find.byType(Positioned), findsWidgets);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('10'), findsOneWidget);
    expect(fake.sfx.where((s) => s == Sfx.coin), hasLength(3));
    await tester.pumpAndSettle();
    expect(find.text('Well done!'), findsNothing);
  });

  testWidgets('with Reduce motion nothing flies: the number just changes', (tester) async {
    final fake = await open(tester, reduceMotion: true);
    await tester.tap(find.text('Collect'));
    await tester.pump();
    expect(find.text('10'), findsOneWidget);
    expect(fake.sfx, [Sfx.reward, Sfx.tap, Sfx.coin]);
    await tester.pumpAndSettle();
    expect(find.text('Well done!'), findsNothing);
  });

  testWidgets('a building moment has its ribbon and its own button', (tester) async {
    await open(tester, ribbon: 'New building!', button: 'Hooray!');
    expect(find.text('New building!'), findsOneWidget);
    await tester.tap(find.text('Hooray!'));
    await tester.pumpAndSettle();
    expect(find.text('Well done!'), findsNothing);
  });

  testWidgets('no coins: the button just closes it', (tester) async {
    await open(tester, coins: 0);
    expect(find.text('+0'), findsNothing);
    await tester.tap(find.text('Collect'));
    await tester.pumpAndSettle();
    expect(find.text('Well done!'), findsNothing);
  });
}
