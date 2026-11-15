import 'dart:math';

import '../components/bananagramsTiles.dart';
import '../game/balanced_draw.dart';
import '../settings/word_level.dart';
import 'daily_easy_words.dart';
import 'daily_seed.dart';
import 'daily_themes.dart';

// Today's Daily puzzle (spec-05): a theme, a secret word from that theme,
// and the 21 letters everyone gets. Everything comes from the UTC date, so
// every player has the same puzzle and it never needs the network or the
// dictionary to start.
class DailyPuzzle {
  final DailyTheme theme;
  final WordLevel level;
  final String secretWord; // uppercase
  final List<String> letters; // exactly level.info.letters, uppercase

  /// What the secret word means, when it is bundled with the app (Sprout
  /// words). Null = look it up.
  final String? meaning;

  const DailyPuzzle({
    required this.theme,
    required this.secretWord,
    required this.letters,
    this.level = WordLevel.wordsmith,
    this.meaning,
  });
}

/// The Wordsmith (full) letter count.
const int kDailyLetterCount = 21;

// The balanced-rack rules for a letter count: (min vowels, max vowels,
// max hard letters, max of any one letter).
({int minVowels, int maxVowels, int maxHard, int maxOfOne}) _rulesFor(int count) => switch (count) {
      <= 8 => (minVowels: 3, maxVowels: 4, maxHard: 0, maxOfOne: 2),
      <= 12 => (minVowels: 4, maxVowels: 5, maxHard: 1, maxOfOne: 2),
      <= 16 => (minVowels: 5, maxVowels: 7, maxHard: 1, maxOfOne: 3),
      _ => (minVowels: 7, maxVowels: 9, maxHard: 2, maxOfOne: 3),
    };

/// Today's puzzle for a word level (spec-06). Every level shares the day's
/// theme. Wordsmith and Builder share the secret word; Explorer gets one of
/// the theme's shorter words (5 letters or fewer); Sprout gets a 3-4 letter
/// word with its meaning bundled.
DailyPuzzle dailyPuzzleFor(DateTime date, [WordLevel level = WordLevel.wordsmith]) {
  final day = dayNumber(date);
  // Themes go round in order; each theme walks through its own words in
  // order, so a secret word doesn't repeat until every word has been used.
  final theme = kDailyThemes[day % kDailyThemes.length];
  final turn = day ~/ kDailyThemes.length;
  String secretWord;
  String? meaning;
  switch (level) {
    case WordLevel.sprout:
      final easy = kEasyWords[theme.id]!;
      final pick = easy[turn % easy.length];
      secretWord = pick.word;
      meaning = pick.meaning;
    case WordLevel.explorer:
      final short = [
        for (final w in theme.words)
          if (w.length <= 5) w,
      ];
      secretWord = short[turn % short.length];
    case WordLevel.builder:
    case WordLevel.wordsmith:
      secretWord = theme.words[turn % theme.words.length];
  }
  // Wordsmith keeps the seed it always had; the other levels get their own.
  final seed = dailySeedForDate(date) + (level == WordLevel.wordsmith ? 0 : level.index + 1);
  return DailyPuzzle(
    theme: theme,
    level: level,
    secretWord: secretWord,
    meaning: meaning,
    letters: dailyLettersFor(secretWord, seed, count: level.info.letters),
  );
}

/// The secret word's letters plus a balanced fill up to [count], shuffled.
/// With no Swap in the Daily these are all the letters the player gets, so
/// the whole set follows the balanced-rack rules. For the full 21: 7-9
/// vowels, at most 2 hard letters (never the same one twice, no Q without
/// a U), and at most 3 of any letter unless the secret word itself needs
/// more. Smaller racks scale those down (see _rulesFor).
List<String> dailyLettersFor(String secretWord, int seed, {int count = kDailyLetterCount}) {
  final random = Random(seed);
  final letters = secretWord.toUpperCase().split('');
  // A full Bananagrams bag, so the fill has the usual letter mix.
  final bag = LetterGenerator.generateLetters(144, seed: seed);
  final rules = _rulesFor(count);

  while (letters.length < count) {
    final slotsLeft = count - letters.length;
    final vowels = letters.where(kVowels.contains).length;
    final hard = letters.where(kHardLetters.contains).toList();
    final hasU = letters.contains('U');

    // null = either type is fine.
    final bool? wantVowel =
        vowels >= rules.maxVowels ? false : (rules.minVowels - vowels >= slotsLeft ? true : null);

    bool passesType(String l) => wantVowel == null || kVowels.contains(l) == wantVowel;
    bool passesHard(String l) {
      if (!kHardLetters.contains(l)) return true;
      if (hard.length >= rules.maxHard || hard.contains(l)) return false;
      return l != 'Q' || hasU;
    }

    bool passesCount(String l) => letters.where((x) => x == l).length < rules.maxOfOne;

    List<int> indicesWhere(bool Function(String) test) => [
          for (int i = 0; i < bag.length; i++)
            if (test(bag[i])) i,
        ];

    var candidates = indicesWhere((l) => passesType(l) && passesHard(l) && passesCount(l));
    // The bag holds far more of every letter type than 21 slots can use,
    // so these fallbacks are only a guard against an endless loop.
    if (candidates.isEmpty) candidates = indicesWhere((l) => passesType(l) && passesHard(l));
    if (candidates.isEmpty) candidates = [for (int i = 0; i < bag.length; i++) i];
    letters.add(bag.removeAt(candidates[random.nextInt(candidates.length)]));
  }

  letters.shuffle(random);
  return letters;
}

/// True if [word] is spelled on the board as a whole across or down run
/// (not just as part of a longer run). The secret word is known to be a
/// real word, so this needs no dictionary.
bool boardContainsWord(List<String?> boardCells, int width, int height, String word) {
  final target = word.toUpperCase();
  bool lineHas(Iterable<String?> line) => line.map((c) => c ?? ' ').join().split(' ').contains(target);
  for (int r = 0; r < height; r++) {
    if (lineHas([for (int c = 0; c < width; c++) boardCells[r * width + c]])) return true;
  }
  for (int c = 0; c < width; c++) {
    if (lineHas([for (int r = 0; r < height; r++) boardCells[r * width + c]])) return true;
  }
  return false;
}

/// A meaning with the secret word itself taken out, so a clue can't just
/// say the answer.
String hideWordInMeaning(String meaning, String word) =>
    meaning.replaceAll(RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false), 'this');
