import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/daily_themes.dart';
import 'package:namer_app/daily/word_of_the_day.dart';
import 'package:namer_app/daily/word_of_the_day_controller.dart';
import 'package:namer_app/village/magic_word.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Read from disk, like the dictionary: no asset bundle needed.
  final list = parseWordsOfTheDay(File('assets/words/word_of_the_day.json').readAsStringSync());

  test('120 words that follow the list rules', () {
    expect(list.length, 120);
    expect(list.map((w) => w.word).toSet().length, 120);

    final dictionary = File('lib_assests/words.txt').readAsLinesSync().map((l) => l.trim().toUpperCase()).toSet();
    final themeWords = {for (final t in kDailyThemes) ...t.words};
    for (final entry in list) {
      final word = entry.word;
      expect(RegExp(r'^[A-Z]{4,7}$').hasMatch(word), isTrue, reason: word);
      expect(dictionary.contains(word), isTrue, reason: '$word is not in words.txt');
      expect(magicWordFor(word), isNull, reason: '$word is a magic word');
      expect(themeWords.contains(word), isFalse, reason: '$word is a Daily theme word');
      expect(entry.meaning.length, lessThanOrEqualTo(80), reason: word);
      expect(entry.meaning.trim(), isNotEmpty, reason: word);
      expect(RegExp('\\b$word\\b', caseSensitive: false).hasMatch(entry.meaning), isFalse,
          reason: "$word's meaning uses the word itself");
    }
  });

  test('the word is the same all UTC day and changes the next day', () {
    final morning = DateTime.utc(2026, 11, 14, 0, 5);
    final night = DateTime.utc(2026, 11, 14, 23, 55);
    final nextDay = DateTime.utc(2026, 11, 15, 0, 5);
    expect(wordOfDayFor(night, list).word, wordOfDayFor(morning, list).word);
    expect(wordOfDayFor(nextDay, list).word, isNot(wordOfDayFor(morning, list).word));
    // Walks the whole list before repeating.
    final seen = {for (int d = 0; d < 120; d++) wordOfDayFor(morning.add(Duration(days: d)), list).word};
    expect(seen.length, 120);
    expect(wordOfDayFor(morning.add(const Duration(days: 120)), list).word, wordOfDayFor(morning, list).word);
  });

  test('claim is true once a day, and survives a save and load', () async {
    SharedPreferences.setMockInitialValues({});
    final today = DateTime.utc(2026, 11, 14, 9);
    final tomorrow = today.add(const Duration(days: 1));

    final controller = WordOfDayController();
    await controller.loaded;
    expect(controller.claimedToday(today), isFalse);
    expect(controller.claim(today), isTrue);
    expect(controller.claim(today), isFalse);
    expect(controller.claimedToday(today), isTrue);
    expect(controller.claimedToday(tomorrow), isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    final reopened = WordOfDayController();
    await reopened.loaded;
    expect(reopened.claimedToday(today), isTrue);
    expect(reopened.claim(today), isFalse);
    expect(reopened.claim(tomorrow), isTrue);
  });
}
