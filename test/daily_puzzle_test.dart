import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/daily_puzzle.dart';
import 'package:namer_app/daily/daily_seed.dart';
import 'package:namer_app/game/balanced_draw.dart';

void main() {
  final start = DateTime.utc(2026, 11, 14, 12);

  test('dayNumber counts whole UTC days from 2026-01-01', () {
    expect(dayNumber(DateTime.utc(2026, 1, 1)), 0);
    expect(dayNumber(DateTime.utc(2026, 1, 1, 23, 59)), 0);
    expect(dayNumber(DateTime.utc(2026, 1, 2)), 1);
    expect(dayNumber(DateTime.utc(2027, 1, 1)), 365);
  });

  test('the same date gives the same puzzle; the next day a different theme', () {
    final a = dailyPuzzleFor(start);
    final b = dailyPuzzleFor(start.add(const Duration(hours: 5)));
    expect(b.theme.id, a.theme.id);
    expect(b.secretWord, a.secretWord);
    expect(b.letters, a.letters);

    final next = dailyPuzzleFor(start.add(const Duration(days: 1)));
    expect(next.theme.id, isNot(a.theme.id));
  });

  test('400 days of puzzles: 21 fair letters that can spell the secret word', () {
    for (int d = 0; d < 400; d++) {
      final puzzle = dailyPuzzleFor(start.add(Duration(days: d)));
      final letters = puzzle.letters;
      final why = 'day $d (${puzzle.secretWord}): ${letters.join()}';
      expect(letters.length, kDailyLetterCount, reason: why);
      expect(puzzle.theme.words.contains(puzzle.secretWord), isTrue, reason: why);

      final left = List<String>.from(letters);
      for (final l in puzzle.secretWord.split('')) {
        expect(left.remove(l), isTrue, reason: why);
      }

      final vowels = letters.where(kVowels.contains).length;
      expect(vowels, inInclusiveRange(7, 9), reason: why);

      final hard = letters.where(kHardLetters.contains).toList();
      expect(hard.length, lessThanOrEqualTo(2), reason: why);
      expect(hard.toSet().length, hard.length, reason: why);
      if (letters.contains('Q')) expect(letters.contains('U'), isTrue, reason: why);

      for (final l in letters.toSet()) {
        final inSecret = puzzle.secretWord.split('').where((x) => x == l).length;
        final limit = inSecret > 3 ? inSecret : 3;
        expect(letters.where((x) => x == l).length, lessThanOrEqualTo(limit), reason: why);
      }
    }
  });

  test('no secret word repeats within 128 days', () {
    final seen = <String>{};
    for (int d = 0; d < 128; d++) {
      expect(seen.add(dailyPuzzleFor(start.add(Duration(days: d))).secretWord), isTrue);
    }
  });
}
