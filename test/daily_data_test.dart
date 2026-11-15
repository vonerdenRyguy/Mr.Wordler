import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/daily_challenge_controller.dart';
import 'package:namer_app/daily/daily_challenge_data.dart';
import 'package:namer_app/daily/daily_tier.dart';
import 'package:namer_app/portfolio/property_tier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('secretWordCoins: 20, 15, 10, 5 for 0-3 clues', () {
    expect([for (int i = 0; i <= 3; i++) secretWordCoins(i)], [20, 15, 10, 5]);
  });

  test('a save from before spec-05 loads with defaults', () {
    final old = {
      'lastPlayedDateKey': '2026-10-02',
      'streak': 3,
      'completions': 4,
      'totalCompletionSeconds': 600,
      'bonusWordsFound': 1,
      'lastResult': {
        'dateKey': '2026-10-02',
        'completed': true,
        'timeSeconds': 150,
        'bonusWordFound': true,
        'tierAwarded': PropertyTier.house.storageKey,
      },
    };
    final data = DailyChallengeData.fromJson(old);
    expect(data.streak, 3);
    expect(data.cluesDateKey, isNull);
    expect(data.cluesUsedOn('2026-10-02'), 0);
    expect(data.lastResult!.themeName, isNull);
    expect(data.lastResult!.secretWord, isNull);
    expect(data.lastResult!.cluesUsed, 0);
    expect(data.lastResult!.bonusWordFound, isTrue);
  });

  test('the new fields save and load', () {
    final data = DailyChallengeData.initial().copyWith(
      cluesDateKey: '2026-11-14',
      cluesUsed: 2,
      lastResult: const DailyResult(
        dateKey: '2026-11-14',
        completed: true,
        timeSeconds: 90,
        bonusWordFound: true,
        tierAwarded: PropertyTier.house,
        themeName: 'Animals',
        secretWord: 'HORSE',
        cluesUsed: 2,
      ),
    );
    final back = DailyChallengeData.fromJson(jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    expect(back.cluesUsedOn('2026-11-14'), 2);
    expect(back.lastResult!.themeName, 'Animals');
    expect(back.lastResult!.secretWord, 'HORSE');
    expect(back.lastResult!.cluesUsed, 2);
  });

  test("clues are counted per day: yesterday's read as 0 today, and stop at 3", () async {
    SharedPreferences.setMockInitialValues({});
    final controller = DailyChallengeController();
    await Future<void>.delayed(Duration.zero);
    final today = DateTime.utc(2026, 11, 14, 9);
    final tomorrow = today.add(const Duration(days: 1));

    expect(controller.cluesUsedToday(today), 0);
    expect(controller.useClue(today), 1);
    expect(controller.useClue(today), 2);
    expect(controller.cluesUsedToday(today), 2);
    expect(controller.cluesUsedToday(tomorrow), 0);
    expect(controller.useClue(today), 3);
    expect(controller.useClue(today), 3);

    expect(controller.useClue(tomorrow), 1);
    expect(controller.cluesUsedToday(tomorrow), 1);

    // Saved, so a fresh controller (the app reopened) still has them.
    await Future<void>.delayed(Duration.zero);
    final reopened = DailyChallengeController();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reopened.cluesUsedToday(tomorrow), 1);
  });
}
