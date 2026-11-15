import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/daily_themes.dart';
import 'package:namer_app/village/magic_word.dart';

void main() {
  test('8 themes of 16 words, each 4-6 uppercase letters', () {
    expect(kDailyThemes.length, 8);
    for (final theme in kDailyThemes) {
      expect(theme.words.length, 16, reason: theme.id);
      for (final word in theme.words) {
        expect(RegExp(r'^[A-Z]{4,6}$').hasMatch(word), isTrue, reason: word);
      }
    }
  });

  test('no word is in two themes, and none is a magic word', () {
    final all = [for (final t in kDailyThemes) ...t.words];
    expect(all.toSet().length, all.length);
    for (final word in all) {
      expect(magicWordFor(word), isNull, reason: word);
    }
  });

  test('every theme word is in the game dictionary', () {
    // Read from disk: the asset bundle can't serve the 1.5MB list in tests.
    final dictionary = File('lib_assests/words.txt').readAsLinesSync().map((l) => l.trim().toUpperCase()).toSet();
    for (final theme in kDailyThemes) {
      for (final word in theme.words) {
        expect(dictionary.contains(word), isTrue, reason: '$word (${theme.id}) is not in words.txt');
      }
    }
  });
}
