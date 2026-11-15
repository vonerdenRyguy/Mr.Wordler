import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'daily_seed.dart';

// Word of the day (spec-05): one friendly word a day with a short meaning,
// from a list bundled with the app (assets/words/word_of_the_day.json), so
// it works offline. Spelling it in your village pays a small reward once
// (see word_of_the_day_controller.dart).
class WordOfDay {
  final String word; // uppercase
  final String meaning;

  const WordOfDay({required this.word, required this.meaning});
}

List<WordOfDay> parseWordsOfTheDay(String json) => [
      for (final entry in jsonDecode(json) as List)
        WordOfDay(
          word: (entry['word'] as String).toUpperCase(),
          meaning: entry['meaning'] as String,
        ),
    ];

// Not cached by the bundle: wordsOfTheDayProvider below already keeps the
// parsed list, so there's no need to hold the raw text as well.
Future<List<WordOfDay>> loadWordsOfTheDay() async =>
    parseWordsOfTheDay(await rootBundle.loadString('assets/words/word_of_the_day.json', cache: false));

/// Walks the list in order, one word per UTC day, and starts again at the
/// end. Changes at the same moment as the Daily puzzle.
WordOfDay wordOfDayFor(DateTime date, List<WordOfDay> list) => list[dayNumber(date) % list.length];

/// The whole list, loaded once. Overridable in tests.
final wordsOfTheDayProvider = FutureProvider<List<WordOfDay>>((ref) => loadWordsOfTheDay());
