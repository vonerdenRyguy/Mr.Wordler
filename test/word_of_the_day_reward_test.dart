// Spelling the Word of the day in the village pays +10 coins, once a day.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/word_of_the_day.dart';
import 'package:namer_app/daily/word_of_the_day_controller.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/portfolio/portfolio_controller.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _size = 500;
const _mid = _size ~/ 2;

void main() {
  final words = parseWordsOfTheDay(File('assets/words/word_of_the_day.json').readAsStringSync());

  Future<ProviderContainer> openVillageWith(WidgetTester tester, String wordOnBoard) async {
    final board = List<String?>.filled(_size * _size, null);
    wordOnBoard.split('').asMap().forEach((i, l) => board[_mid * _size + _mid - 3 + i] = l);
    SharedPreferences.setMockInitialValues({
      'infiniteEstateVillageSave': jsonEncode({
        'boardCells': board,
        'rackCells': List<String>.filled(10, 'E'),
        'pool': List<String>.filled(50, 'E'),
        'dealtLetters': [...wordOnBoard.split(''), ...List<String>.filled(10, 'E')],
        'lastCashedOutScore': 0,
        'discoveredWords': <String>[],
        'saveVersion': 2,
      }),
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wordCheckProvider.overrideWithValue((w) async => w.toUpperCase() == wordOnBoard),
        wordsOfTheDayProvider.overrideWith((ref) async => words),
      ],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.text('Visit your village')));
    expect(container.read(portfolioProvider).currency, 0);
    await tester.tap(find.text('Visit your village'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20));
    return container;
  }

  testWidgets("today's word on the board pays 10 coins once, and Home then says Done", (tester) async {
    final today = wordOfDayFor(DateTime.now(), words).word;
    final container = await openVillageWith(tester, today);

    expect(tester.takeException(), isNull);
    expect(container.read(portfolioProvider).currency, kWordOfDayCoins);
    expect(container.read(wordOfDayProvider.notifier).claimedToday(DateTime.now()), isTrue);
    expect(find.textContaining('Word of the day!'), findsOneWidget);

    // Leaving and coming back refreshes the board again: no second reward.
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave Village'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Visit your village'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('+10 coins'), findsNothing);
    final coinsBefore = container.read(portfolioProvider).currency;

    await tester.tap(find.text('Visit your village'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20));
    expect(container.read(portfolioProvider).currency, coinsBefore);
  });

  testWidgets('another word on the board pays nothing', (tester) async {
    final today = wordOfDayFor(DateTime.now(), words).word;
    final other = words.firstWhere((w) => w.word != today).word;
    final container = await openVillageWith(tester, other);

    expect(container.read(portfolioProvider).currency, 0);
    expect(container.read(wordOfDayProvider.notifier).claimedToday(DateTime.now()), isFalse);
    expect(find.textContaining('Word of the day!'), findsNothing);
  });
}
