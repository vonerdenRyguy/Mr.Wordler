import 'dart:math';

class LetterGenerator {

  // Map of available letters that the user may use
  // and their associated number for each letter
  static const Map<String, int> letterCounts = {
    'A': 13,
    'B': 3,
    'C': 3,
    'D': 6,
    'E': 18,
    'F': 3,
    'G': 4,
    'H': 3,
    'I': 12,
    'J': 2,
    'K': 2,
    'L': 5,
    'M': 3,
    'N': 8,
    'O': 11,
    'P': 3,
    'Q': 2,
    'R': 9,
    'S': 6,
    'T': 9,
    'U': 6,
    'V': 3,
    'W': 3,
    'X': 2,
    'Y': 3,
    'Z': 2,
  };

  // Approximate relative Scrabble-style point value per letter, used by
  // modes (e.g. Infinite Estate) that score placed words.
  static const Map<String, int> letterPoints = {
    'A': 1, 'B': 3, 'C': 3, 'D': 2, 'E': 1, 'F': 4, 'G': 2, 'H': 4,
    'I': 1, 'J': 8, 'K': 5, 'L': 1, 'M': 3, 'N': 1, 'O': 1, 'P': 3,
    'Q': 10, 'R': 1, 'S': 1, 'T': 1, 'U': 1, 'V': 4, 'W': 4, 'X': 8,
    'Y': 4, 'Z': 10,
  };

  // Generates `count` letters from the weighted pool. If `seed` is given,
  // the shuffle is deterministic for that seed (used by the Daily Estate
  // Challenge so every player gets the same letters on a given date);
  // otherwise it's a fresh random draw each call.
  //
  // The base distribution totals 144 letters (standard Bananagrams); for
  // `count` above that (e.g. Infinite Estate's much larger pool) the
  // distribution repeats enough times to cover it, preserving the same
  // relative letter frequencies rather than just running out.
  static List<String> generateLetters(int count, {int? seed}) {
    List<String> baseLetters = [];
    letterCounts.forEach((letter, n) {
      for (int i = 0; i < n; i++) {
        baseLetters.add(letter);
      }
    });

    final repeats = (count / baseLetters.length).ceil();
    List<String> allLetters = [];
    for (int i = 0; i < repeats; i++) {
      allLetters.addAll(baseLetters);
    }

    allLetters.shuffle(seed != null ? Random(seed) : Random());

    // Return the first 'count' letters (should be the starting letters)
    return allLetters.sublist(0, count);
  }
}
