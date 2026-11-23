// spec-11: Home is three pages you swipe between (Me | Play | Family), with
// a first-time intro card and Mr. W's tips.

import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/daily_seed.dart';
import 'package:namer_app/daily/word_of_the_day.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/screens/home_tips.dart';
import 'package:namer_app/settings/settings_controller.dart';
import 'package:namer_app/ui/home_nav.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart';
import 'widget_test.dart' show loadAppFonts;

void main() {
  setUpAll(loadAppFonts);
  final words = parseWordsOfTheDay(File('assets/words/word_of_the_day.json').readAsStringSync());

  Future<void> pumpHome(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [wordsOfTheDayProvider.overrideWith((ref) async => words)],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
  }

  const playTip = "Try today's Daily puzzle. There's a new one every day!";

  testWidgets('the first time, a card says to swipe; Got it hides it for good', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHome(tester);
    expect(find.text('Swipe to look around'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Swipe to look around'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SettingsController.homeIntroSeenKey), isTrue);
  });

  testWidgets('swiping moves between Me, Play and Family; the tabs follow', (tester) async {
    SharedPreferences.setMockInitialValues({SettingsController.homeIntroSeenKey: true});
    await pumpHome(tester);
    expect(find.byKey(const ValueKey('globe-village-0')), findsOneWidget);

    // Swipe right: Me.
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Journal'), findsOneWidget);
    expect(find.byKey(const ValueKey('globe-village-0')), findsNothing);

    // Swipe left twice: Play, then Family.
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('globe-village-0')), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Play with your family'), findsOneWidget);
    expect(tester.getSemantics(find.text('Family').last).hasFlag(SemanticsFlag.isSelected), isTrue);
  });

  testWidgets("Mr. W's tip shows on Play; the X hides it for today", (tester) async {
    SharedPreferences.setMockInitialValues({SettingsController.homeIntroSeenKey: true});
    await pumpHome(tester);
    expect(find.text(playTip), findsOneWidget);

    await tester.tap(find.byTooltip('Hide tip'));
    await tester.pumpAndSettle();
    expect(find.text(playTip), findsNothing);
    final saved = jsonDecode((await SharedPreferences.getInstance()).getString(HiddenTipsController.prefsKey)!);
    expect(saved['day'], dailyDateKey(DateTime.now()));
    expect(saved['ids'], ['daily']);
  });

  testWidgets('a tip hidden yesterday comes back; Show tips off hides them all', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsController.homeIntroSeenKey: true,
      HiddenTipsController.prefsKey: jsonEncode({
        'day': dailyDateKey(DateTime.now().subtract(const Duration(days: 1))),
        'ids': ['daily'],
      }),
    });
    await pumpHome(tester);
    expect(find.text(playTip), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.text(playTip)));
    await container.read(settingsProvider.notifier).setShowTips(false);
    await tester.pumpAndSettle();
    expect(find.text(playTip), findsNothing);
    expect(find.byTooltip('Hide tip'), findsNothing);
  });

  testWidgets("on the Samsung (text 1.15, with a tip showing) Me still fits one screen", (tester) async {
    SharedPreferences.setMockInitialValues({SettingsController.homeIntroSeenKey: true});
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const size = Size(411, 891);
    await pumpHome(tester, size: size);
    await goToHomePage(tester, 'Me');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Spell the word of the day in your village for +10 coins.'), findsOneWidget);
    for (final label in ['Stats', 'Word level', 'Journal', 'Homes', 'Villagers']) {
      final box = tester.getRect(find.text(label));
      expect(box.bottom, lessThan(tester.getRect(find.byType(TipBar)).top), reason: label);
    }
  });

  testWidgets('at Extra large text every page still works without overflow', (tester) async {
    SharedPreferences.setMockInitialValues({SettingsController.homeIntroSeenKey: true, 'textSizeStep': 2});
    await pumpHome(tester);
    expect(tester.takeException(), isNull);
    for (final tab in ['Me', 'Family', 'Play']) {
      await goToHomePage(tester, tab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    // Play's badge and goal bar are on screen.
    for (final label in ['Daily puzzle', 'Light the Great Lantern']) {
      expect(const Rect.fromLTWH(0, 0, 390, 844).contains(tester.getRect(find.text(label)).bottomRight), isTrue,
          reason: label);
    }
  });

  testWidgets('Me (spec-12b): one hero, one strip, a row of round buttons that open their pages', (tester) async {
    SharedPreferences.setMockInitialValues({SettingsController.homeIntroSeenKey: true, 'wordLevel': 'sprout'});
    await pumpHome(tester);
    await goToHomePage(tester, 'Me');
    await tester.pumpAndSettle();
    expect(find.text('Word of the day'), findsOneWidget);
    expect(find.text('WORD OF THE DAY'), findsNothing);
    await tester.tap(find.text('Word level'));
    await tester.pumpAndSettle();
    expect(find.text('Sprout'), findsWidgets);
    Navigator.of(tester.element(find.text('Sprout').first)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Journal'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  group('Play page (spec-12)', () {
    Map<String, Object> prefs({bool played = false}) => {
          SettingsController.homeIntroSeenKey: true,
          'wordLevel': 'wordsmith',
          if (played) 'dailyChallengeData': jsonEncode({'lastPlayedDateKey': dailyDateKey(DateTime.now()), 'streak': 1}),
        };

    // Everything on Play sits above the tab bar and below the top bar.
    void fitsBetweenBars(WidgetTester tester, List<String> labels) {
      final tabsTop = tester.getRect(find.byType(HomeTabBar)).top;
      final dotsTop = tester.getRect(find.byType(PageDots)).top;
      for (final label in labels) {
        final box = tester.getRect(find.text(label));
        expect(box.bottom, lessThanOrEqualTo(min(tabsTop, dotsTop)), reason: label);
        expect(box.top, greaterThan(40), reason: label);
      }
    }

    testWidgets('before the Daily is played, its badge opens it and wears a red !', (tester) async {
      SharedPreferences.setMockInitialValues(prefs());
      await pumpHome(tester);
      expect(find.text('!'), findsOneWidget);
      expect(find.byKey(const ValueKey('globe-village-0')), findsOneWidget);
      expect(find.text('Light the Great Lantern'), findsOneWidget);
      expect(find.text('PLAY'), findsNothing);
      fitsBetweenBars(tester, ['Daily puzzle', 'Light the Great Lantern']);
      await tester.tap(find.text('Daily puzzle'));
      await tester.pumpAndSettle();
      expect(find.text('Clue'), findsOneWidget); // the Daily round
    });

    testWidgets('tapping your village on the globe goes in', (tester) async {
      SharedPreferences.setMockInitialValues(prefs(played: true));
      await pumpHome(tester);
      expect(find.text('!'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('globe-village-0')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20));
      expect(find.text('Swap'), findsOneWidget); // the village
    });

    testWidgets('Time Attack is gone from Home; the Daily badge says so when played', (tester) async {
      SharedPreferences.setMockInitialValues(prefs(played: true));
      await pumpHome(tester);
      expect(find.text('Time Attack'), findsNothing);
      await tester.tap(find.text('Daily puzzle'));
      await tester.pumpAndSettle();
      expect(find.text("You've already played today!"), findsOneWidget);
    });

    testWidgets('fits the Samsung at text 1.15, tip showing', (tester) async {
      SharedPreferences.setMockInitialValues(prefs());
      tester.platformDispatcher.textScaleFactorTestValue = 1.15;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHome(tester, size: const Size(411, 891));
      expect(tester.takeException(), isNull);
      expect(find.text(playTip), findsOneWidget);
      fitsBetweenBars(tester, ['Daily puzzle', 'Light the Great Lantern']);
      expect(tester.getRect(find.text('Light the Great Lantern')).bottom,
          lessThan(tester.getRect(find.byType(TipBar)).top));
    });
  });

  group('homeTipFor', () {
    TipFacts facts({
      bool played = false,
      int? buildings = 1,
      int waiting = 0,
      bool family = false,
      bool solved = false,
      bool claimed = true,
      String? asker,
      String? letter,
    }) =>
        TipFacts(
          playedToday: played,
          buildings: buildings,
          waitingFromFamily: waiting,
          hasFamily: family,
          familyWordSolved: solved,
          wordOfDayClaimed: claimed,
          askerName: asker,
          askedLetter: letter,
        );

    test('Play: family first, then the Daily, then a first building', () {
      expect(homeTipFor(HomePage.play, facts(waiting: 2))!.id, 'family-waiting');
      expect(homeTipFor(HomePage.play, facts())!.id, 'daily');
      expect(homeTipFor(HomePage.play, facts(played: true, buildings: 0))!.id, 'first-building');
      expect(homeTipFor(HomePage.play, facts(played: true)), isNull);
      // Still loading the village: say nothing yet.
      expect(homeTipFor(HomePage.play, facts(played: true, buildings: null)), isNull);
    });

    test('Family: a request names the letter with a or an', () {
      expect(homeTipFor(HomePage.family, facts(asker: 'Nana', letter: 'R'))!.text, 'Nana needs an R. Tap Send to help.');
      expect(homeTipFor(HomePage.family, facts(asker: 'Leo', letter: 'B'))!.text, 'Leo needs a B. Tap Send to help.');
      expect(homeTipFor(HomePage.family, facts(family: true))!.id, 'family-word');
      expect(homeTipFor(HomePage.family, facts(family: true, played: true)), isNull);
      expect(homeTipFor(HomePage.family, facts(family: true, solved: true)), isNull);
      expect(homeTipFor(HomePage.family, facts()), isNull);
    });

    test('Me: the word of the day until it is claimed', () {
      expect(homeTipFor(HomePage.me, facts(claimed: false))!.id, 'word-of-day');
      expect(homeTipFor(HomePage.me, facts()), isNull);
    });
  });
}
