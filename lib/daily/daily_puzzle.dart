import 'dart:math';

import '../components/bananagramsTiles.dart';
import '../game/balanced_draw.dart';
import 'daily_seed.dart';
import 'daily_themes.dart';

// Today's Daily puzzle (spec-05): a theme, a secret word from that theme,
// and the 21 letters everyone gets. Everything comes from the UTC date, so
// every player has the same puzzle and it never needs the network or the
// dictionary to start.
class DailyPuzzle {
  final DailyTheme theme;
  final String secretWord; // uppercase
  final List<String> letters; // exactly kDailyLetterCount, uppercase

  const DailyPuzzle({required this.theme, required this.secretWord, required this.letters});
}

const int kDailyLetterCount = 21;
const int _minVowels = 7;
const int _maxVowels = 9;
const int _maxHard = 2;
const int _maxOfOneLetter = 3;

DailyPuzzle dailyPuzzleFor(DateTime date) {
  final day = dayNumber(date);
  // Themes go round in order; each theme walks through its own words in
  // order, so a secret word doesn't repeat until every word has been used.
  final theme = kDailyThemes[day % kDailyThemes.length];
  final secretWord = theme.words[(day ~/ kDailyThemes.length) % theme.words.length];
  return DailyPuzzle(
    theme: theme,
    secretWord: secretWord,
    letters: dailyLettersFor(secretWord, dailySeedForDate(date)),
  );
}

/// The secret word's letters plus a balanced fill up to 21, shuffled. With
/// no Swap in the Daily these are all the letters the player gets, so the
/// whole set follows the balanced-rack rules: 7-9 vowels, at most 2 hard
/// letters (never the same one twice, no Q without a U), and at most 3 of
/// any letter unless the secret word itself needs more.
List<String> dailyLettersFor(String secretWord, int seed) {
  final random = Random(seed);
  final letters = secretWord.toUpperCase().split('');
  // A full Bananagrams bag, so the fill has the usual letter mix.
  final bag = LetterGenerator.generateLetters(144, seed: seed);

  while (letters.length < kDailyLetterCount) {
    final slotsLeft = kDailyLetterCount - letters.length;
    final vowels = letters.where(kVowels.contains).length;
    final hard = letters.where(kHardLetters.contains).toList();
    final hasU = letters.contains('U');

    // null = either type is fine.
    final bool? wantVowel = vowels >= _maxVowels ? false : (_minVowels - vowels >= slotsLeft ? true : null);

    bool passesType(String l) => wantVowel == null || kVowels.contains(l) == wantVowel;
    bool passesHard(String l) {
      if (!kHardLetters.contains(l)) return true;
      if (hard.length >= _maxHard || hard.contains(l)) return false;
      return l != 'Q' || hasU;
    }

    bool passesCount(String l) => letters.where((x) => x == l).length < _maxOfOneLetter;

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
