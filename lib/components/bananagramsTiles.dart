import 'dart:math';


class LetterGenerator {

  static List<String> generateLetters(int count) {
    final letterCounts = {
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

    List<String> allLetters = [];
    letterCounts.forEach((letter, count) {
      for (int i = 0; i < count; i++) {
        allLetters.add(letter);
      }
    });

    allLetters.shuffle(Random());

    return allLetters.sublist(0, count); // Return the first 'count' letters
  }

  List<String>tradeIn(List<String> allLetters, String takenLetter) {
    //List<String> shuffled = [];
    allLetters.add(takenLetter);
    allLetters.shuffle(Random());
    allLetters.length == 3;
    return allLetters;
  }
}