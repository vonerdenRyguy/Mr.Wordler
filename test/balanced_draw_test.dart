import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/balanced_draw.dart';

void main() {
  const mixedPool = ['A', 'E', 'I', 'O', 'U', 'B', 'C', 'D', 'T', 'S', 'J', 'K', 'Q', 'V', 'X', 'Z'];

  String drawOnce(List<String?> rack, List<String> pool, int seed) =>
      drawBalanced(List<String>.from(pool), rack, Random(seed));

  test('a rack with 1 vowel always draws a vowel', () {
    final rack = ['A', 'B', 'C', 'D', 'T', 'S', 'R', 'N', 'L'];
    for (int seed = 0; seed < 200; seed++) {
      expect(kVowels, contains(drawOnce(rack, mixedPool, seed)));
    }
  });

  test('a rack with 6 vowels always draws a consonant', () {
    final rack = ['A', 'E', 'I', 'O', 'U', 'A', 'B', 'C', 'D'];
    for (int seed = 0; seed < 200; seed++) {
      expect(kVowels, isNot(contains(drawOnce(rack, mixedPool, seed))));
    }
  });

  test('a rack with 2 hard letters never draws another hard letter', () {
    final rack = ['Z', 'X', 'A', 'E', 'I', 'B', 'C', 'D', 'S'];
    final pool = ['J', 'K', 'Q', 'V', 'X', 'Z', 'J', 'K', 'Q', 'V', 'T'];
    for (int seed = 0; seed < 200; seed++) {
      expect(drawOnce(rack, pool, seed), 'T');
    }
  });

  test('a rack holding Z never draws a second Z', () {
    final rack = ['Z', 'A', 'E', 'I', 'B', 'C', 'D', 'S', 'T'];
    final pool = ['Z', 'Z', 'Z', 'Z', 'B'];
    for (int seed = 0; seed < 200; seed++) {
      expect(drawOnce(rack, pool, seed), 'B');
    }
  });

  test('Q is only drawn when the rack holds a U', () {
    final noU = ['A', 'E', 'I', 'B', 'C', 'D', 'S', 'T', 'R'];
    for (int seed = 0; seed < 200; seed++) {
      expect(drawOnce(noU, ['Q', 'Q', 'B'], seed), 'B');
    }
    final withU = ['U', 'E', 'I', 'B', 'C', 'D', 'S', 'T', 'R'];
    final draws = {for (int seed = 0; seed < 200; seed++) drawOnce(withU, ['Q', 'B'], seed)};
    expect(draws, contains('Q'));
  });

  test('a pool of only Q still gives Q (last fallback) and empties the pool', () {
    final pool = ['Q'];
    final drawn = drawBalanced(pool, ['A', 'B', 'C'], Random(1));
    expect(drawn, 'Q');
    expect(pool, isEmpty);
  });

  test('the drawn letter is removed from the pool, exactly one', () {
    final pool = List<String>.from(mixedPool);
    final drawn = drawBalanced(pool, ['A', 'E', 'I', 'B', 'C'], Random(7));
    expect(pool.length, mixedPool.length - 1);
    final counts = <String, int>{};
    for (final l in mixedPool) {
      counts[l] = (counts[l] ?? 0) + 1;
    }
    expect(pool.where((l) => l == drawn).length, counts[drawn]! - 1);
  });
}
