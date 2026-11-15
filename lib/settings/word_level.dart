import 'package:flutter/painting.dart';

import '../ui/tokens.dart';

// Word levels (spec-06): how big the player's Daily puzzle is. Picked by
// the player (never worked out from an age) and changeable any time in
// Settings. Every level earns the same coins.
enum WordLevel { sprout, explorer, builder, wordsmith }

/// How one of a level's clues helps.
enum ClueKind { firstLetter, lastLetter, secondLetter, meaning, wholeWord }

class WordLevelInfo {
  const WordLevelInfo({
    required this.name,
    required this.goodFor,
    required this.summary,
    required this.detail,
    required this.letters,
    required this.boardSize,
    required this.clues,
    required this.leftoverAllowed,
    required this.showClock,
    required this.color,
  });

  final String name;
  final String goodFor;
  final String summary;
  final String detail;

  /// Letters dealt, all at once (no pool, no Swap).
  final int letters;

  /// The board is boardSize x boardSize.
  final int boardSize;

  /// The clue ladder, in order. Empty = Sprout: no limit, each clue shows
  /// the next letter of the hidden word.
  final List<ClueKind> clues;

  /// A round can finish with this many letters still in the rack.
  final int leftoverAllowed;

  /// Sprout and Explorer show no clock (the time is still saved).
  final bool showClock;
  final Color color;

  bool get unlimitedClues => clues.isEmpty;

  /// Sprout: the round is finished as soon as the hidden word is spelled.
  bool get finishOnSecretWord => unlimitedClues;
}

const _standardClues = [ClueKind.firstLetter, ClueKind.meaning, ClueKind.wholeWord];

extension WordLevelDetails on WordLevel {
  WordLevelInfo get info => switch (this) {
        WordLevel.sprout => const WordLevelInfo(
            name: 'Sprout',
            goodFor: 'Good for about 5 to 7',
            summary: '8 letters. Find the hidden word.',
            detail: 'Short words, as many clues as you like.',
            letters: 8,
            boardSize: 6,
            clues: [],
            leftoverAllowed: 8,
            showClock: false,
            color: WColors.leaf,
          ),
        WordLevel.explorer => const WordLevelInfo(
            name: 'Explorer',
            goodFor: 'Good for about 8 to 11',
            summary: '12 letters. 5 clues.',
            detail: 'You can finish with 2 letters left over.',
            letters: 12,
            boardSize: 8,
            clues: [
              ClueKind.firstLetter,
              ClueKind.lastLetter,
              ClueKind.meaning,
              ClueKind.secondLetter,
              ClueKind.wholeWord,
            ],
            leftoverAllowed: 2,
            showClock: false,
            color: WColors.sky,
          ),
        WordLevel.builder => const WordLevelInfo(
            name: 'Builder',
            goodFor: 'Good for about 12 to 17',
            summary: '16 letters. 3 clues.',
            detail: 'Use every letter.',
            letters: 16,
            boardSize: 10,
            clues: _standardClues,
            leftoverAllowed: 0,
            showClock: true,
            color: WColors.coral,
          ),
        WordLevel.wordsmith => const WordLevelInfo(
            name: 'Wordsmith',
            goodFor: 'Good for grown-ups',
            summary: '21 letters. 3 clues.',
            detail: 'The full puzzle.',
            letters: 21,
            boardSize: 10,
            clues: _standardClues,
            leftoverAllowed: 0,
            showClock: true,
            color: WColors.sun,
          ),
      };
}

/// The level saved under [name], or null for anything unknown.
WordLevel? wordLevelFromName(String? name) {
  for (final level in WordLevel.values) {
    if (level.name == name) return level;
  }
  return null;
}
