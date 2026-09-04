import 'dart:math';

import 'package:flutter/services.dart';

const int _letterA = 65; // 'A'.codeUnitAt(0)

Future<String> _loadDictionaryAsset() => rootBundle.loadString('lib_assests/words.txt');

// Picks today's hidden bonus word: a dictionary word guaranteed to be
// formable purely from the day's dealt letters (respecting how many of
// each letter are available). The pick is deterministic for a given seed
// + letter set, so it's the same for everyone playing that date, chosen
// once rather than re-rolled per attempt.
//
// `loadDictionary` defaults to the real word list and should only ever be
// overridden in tests: flutter_test's mocked asset channel hangs on
// messages roughly above 45-90KB, which this file is well over (it's
// ~1.5MB) -- that's purely a widget-test-harness limitation (rootBundle
// reads the same file fine in a real run, which is how word validation
// against this exact asset already works in the shipped app), but it
// means tests need to inject a smaller stand-in dictionary.
Future<String?> pickBonusWord(
  List<String> dealtLetters,
  int seed, {
  Future<String> Function() loadDictionary = _loadDictionaryAsset,
}) async {
  final content = await loadDictionary();

  // Fixed-size int array keyed by letter (A=0..Z=25) rather than a Map --
  // this runs once per candidate word across ~149k dictionary entries, so
  // avoiding a Map allocation/hash per word matters for how long the
  // player waits for the puzzle to load.
  final baseCounts = List<int>.filled(26, 0);
  for (final letter in dealtLetters) {
    final idx = letter.codeUnitAt(0) - _letterA;
    if (idx >= 0 && idx < 26) baseCounts[idx]++;
  }

  bool isFormable(String upperWord) {
    final remaining = List<int>.from(baseCounts);
    for (int i = 0; i < upperWord.length; i++) {
      final idx = upperWord.codeUnitAt(i) - _letterA;
      if (idx < 0 || idx >= 26 || remaining[idx] <= 0) return false;
      remaining[idx]--;
    }
    return true;
  }

  // Medium-length words make for a discoverable-but-not-trivial bonus
  // target; the file is already in a fixed, deterministic order so no
  // extra sort is needed for the seeded pick below to be reproducible.
  final candidates = <String>[];
  for (final rawLine in content.split('\n')) {
    final word = rawLine.trim();
    if (word.length < 4 || word.length > 7) continue;
    if (isFormable(word.toUpperCase())) candidates.add(word);
  }

  if (candidates.isEmpty) return null;
  return candidates[Random(seed).nextInt(candidates.length)];
}
