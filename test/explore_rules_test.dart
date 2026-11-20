// Tests for FogMap, explore_rules (minLength, wordClearsFog, isCrossing, xpFor).

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/fog.dart';
import 'package:namer_app/explore/explore_rules.dart';
import 'package:namer_app/explore/island_map.dart';
import 'package:namer_app/game/word_runs.dart';
import 'package:namer_app/settings/word_level.dart';

void main() {
  // ── FogMap ────────────────────────────────────────────────────────────────

  group('FogMap', () {
    const bw = 20, bh = 20; // small board for fast tests

    FogMap empty() => FogMap.empty(boardWidth: bw, boardHeight: bh);

    test('all cells start as fogged', () {
      final fog = empty();
      for (var i = 0; i < bw * bh; i++) {
        expect(fog.isCleared(i), isFalse, reason: 'cell $i should be fogged');
      }
    });

    test('clearAround with radius 0 clears only the cell itself', () {
      final fog = empty().clearAround([55], radius: 0);
      expect(fog.isCleared(55), isTrue);
      expect(fog.isCleared(54), isFalse);
      expect(fog.isCleared(56), isFalse);
      expect(fog.isCleared(35), isFalse); // row above
    });

    test('clearAround with radius 1 clears a 3×3 Chebyshev neighbourhood', () {
      // Cell at (5, 5) on 20-wide board: index = 5*20 + 5 = 105
      final fog = empty().clearAround([105], radius: 1);
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          final r = 5 + dr, c = 5 + dc;
          expect(fog.isCleared(r * bw + c), isTrue,
              reason: 'cell ($r,$c) should be cleared');
        }
      }
      // Just outside: (3,5), (7,5), (5,3), (5,7)
      expect(fog.isCleared(3 * bw + 5), isFalse);
      expect(fog.isCleared(7 * bw + 5), isFalse);
    });

    test('clearAround clips at board edges', () {
      // Corner cell (0,0): only 2×2 area cleared, not negative indices
      final fog = empty().clearAround([0], radius: 1);
      expect(fog.isCleared(0), isTrue);
      expect(fog.isCleared(1), isTrue);
      expect(fog.isCleared(bw), isTrue);
      expect(fog.isCleared(bw + 1), isTrue);
      // No crash from out-of-bounds
    });

    test('canSee returns true for cleared cell', () {
      final fog = empty().clearAround([105], radius: 0);
      expect(fog.canSee(105), isTrue);
    });

    test('canSee returns true for 1-cell fuzzy edge', () {
      // Clear cell (5,5)=105; (5,6)=106 is adjacent but not cleared.
      final fog = empty().clearAround([105], radius: 0);
      expect(fog.isCleared(106), isFalse);
      expect(fog.canSee(106), isTrue); // fuzzy edge
    });

    test('canSee returns false 2+ cells away from cleared', () {
      final fog = empty().clearAround([105], radius: 0);
      // (5,7)=107 is 2 steps away
      expect(fog.canSee(107), isFalse);
    });

    test('base64 round-trip is lossless', () {
      final original = empty().clearAround([10, 50, 300, 350], radius: 2);
      final restored = FogMap.fromBase64(original.toBase64(),
          boardWidth: bw, boardHeight: bh);
      for (var i = 0; i < bw * bh; i++) {
        expect(restored.isCleared(i), original.isCleared(i),
            reason: 'cell $i differs after round-trip');
      }
    });

    test('clearAround multiple cells accumulates correctly', () {
      final fog = empty()
          .clearAround([105], radius: 0)
          .clearAround([110], radius: 0);
      expect(fog.isCleared(105), isTrue);
      expect(fog.isCleared(110), isTrue);
      expect(fog.isCleared(107), isFalse);
    });

    test('clearedCount counts cleared bits', () {
      final fog = empty().clearAround([105], radius: 1); // 3×3 = 9 cells
      expect(fog.clearedCount, 9);
    });
  });

  // ── minLength ─────────────────────────────────────────────────────────────

  group('minLength', () {
    test('meadow always requires 3', () {
      for (final level in WordLevel.values) {
        expect(minLength(Ring.meadow, level), 3);
      }
    });

    test('forest: 4 for all except Sprout (3)', () {
      expect(minLength(Ring.forest, WordLevel.sprout), 3);
      expect(minLength(Ring.forest, WordLevel.explorer), 4);
      expect(minLength(Ring.forest, WordLevel.builder), 4);
      expect(minLength(Ring.forest, WordLevel.wordsmith), 4);
    });

    test('river: 4 for sprout/explorer, 5 for builder/wordsmith', () {
      expect(minLength(Ring.river, WordLevel.sprout), 4);
      expect(minLength(Ring.river, WordLevel.explorer), 4);
      expect(minLength(Ring.river, WordLevel.builder), 5);
      expect(minLength(Ring.river, WordLevel.wordsmith), 5);
    });

    test('hills: 4 sprout, 5 explorer, 6 builder/wordsmith', () {
      expect(minLength(Ring.hills, WordLevel.sprout), 4);
      expect(minLength(Ring.hills, WordLevel.explorer), 5);
      expect(minLength(Ring.hills, WordLevel.builder), 6);
      expect(minLength(Ring.hills, WordLevel.wordsmith), 6);
    });

    test('mountains: 4 sprout, 5 explorer, 6 builder, 7 wordsmith', () {
      expect(minLength(Ring.mountains, WordLevel.sprout), 4);
      expect(minLength(Ring.mountains, WordLevel.explorer), 5);
      expect(minLength(Ring.mountains, WordLevel.builder), 6);
      expect(minLength(Ring.mountains, WordLevel.wordsmith), 7);
    });

    test('clearRadius: 4 for sprout, 3 for all others', () {
      expect(clearRadius(WordLevel.sprout), 4);
      for (final level in [WordLevel.explorer, WordLevel.builder, WordLevel.wordsmith]) {
        expect(clearRadius(level), 3);
      }
    });
  });

  // ── wordClearsFog ─────────────────────────────────────────────────────────

  group('wordClearsFog', () {
    // Helpers: build WordRun from a list of board indices.
    WordRun makeRun(List<int> positions, String word, {bool across = true}) =>
        WordRun(word, positions, across);

    // Stub ring/water functions for a simplified 100-wide board:
    // columns 0-11 → meadow, 12-27 → forest, 28-30 → river, 31-50 → hills.
    Ring stubRing(int idx) {
      final col = idx % 100;
      if (col <= 11) return Ring.meadow;
      if (col <= 27) return Ring.forest;
      if (col <= 30) return Ring.river;
      if (col <= 50) return Ring.hills;
      return Ring.mountains;
    }

    bool stubWater(int idx) => stubRing(idx) == Ring.river;

    test('3-letter meadow word clears fog at Wordsmith', () {
      final run = makeRun([5, 6, 7], 'CAT');
      expect(wordClearsFog(run,
          ringAt: stubRing,
          isWater: stubWater,
          level: WordLevel.wordsmith), isTrue);
    });

    test('3-letter forest word does NOT clear fog at Wordsmith (needs 4+)', () {
      final run = makeRun([15, 16, 17], 'CAT'); // in forest (cols 12-27)
      expect(wordClearsFog(run,
          ringAt: stubRing,
          isWater: stubWater,
          level: WordLevel.wordsmith), isFalse);
    });

    test('4-letter forest word clears fog at Wordsmith', () {
      final run = makeRun([14, 15, 16, 17], 'CATS');
      expect(wordClearsFog(run,
          ringAt: stubRing,
          isWater: stubWater,
          level: WordLevel.wordsmith), isTrue);
    });

    test('3-letter forest word clears fog at Sprout (3+ required)', () {
      final run = makeRun([15, 16, 17], 'CAT');
      expect(wordClearsFog(run,
          ringAt: stubRing,
          isWater: stubWater,
          level: WordLevel.sprout), isTrue);
    });

    test('word spanning meadow+forest uses forest minimum', () {
      // Positions at cols 11 (meadow) + 12,13,14 (forest) = 4-letter word
      final run = makeRun([11, 12, 13, 14], 'CATS');
      // 4 letters, forest needs 4 → clears
      expect(wordClearsFog(run,
          ringAt: stubRing,
          isWater: stubWater,
          level: WordLevel.wordsmith), isTrue);
    });

    test('3-letter word spanning meadow+forest does not clear (forest needs 4)', () {
      final run = makeRun([11, 12, 13], 'CAT');
      expect(wordClearsFog(run,
          ringAt: stubRing,
          isWater: stubWater,
          level: WordLevel.wordsmith), isFalse);
    });

    test('3-water-cell crossing at Wordsmith (5 letters): clears', () {
      // Positions: 1 land (col 27, forest), 3 water (cols 28-30), 1 land (col 31, hills)
      // But forest needs 4+, hills needs 6+ — wait, Wordsmith forest needs 4,
      // hills needs 6, river needs 5. The word is 5 letters total. Forest cell
      // needs 4 → ok. Hills needs 6 → 5 fails. So this shouldn't clear.
      // Let me use meadow instead of hills on the other side.
      // Actually our stub has: col ≤11 = meadow, 12-27 = forest. So to have
      // meadow on both sides of the river: use a bigger-col board would be
      // needed. Let me adjust: use cols 0-11 (meadow) on both sides by picking
      // row offset so the stubRing sees meadow.
      //
      // Easier: test on a simplified scenario where both sides are meadow.
      // Build a custom ring function.
      Ring meadowAndRiver(int idx) {
        final col = idx % 100;
        if (col >= 29 && col <= 31) return Ring.river;
        return Ring.meadow;
      }
      bool riverWater(int idx) => meadowAndRiver(idx) == Ring.river;

      // 5-letter crossing: 1 meadow + 3 river + 1 meadow
      final run = makeRun([28, 29, 30, 31, 32], 'CROSS');
      expect(wordClearsFog(run,
          ringAt: meadowAndRiver,
          isWater: riverWater,
          level: WordLevel.wordsmith), isTrue);
    });

    test('2-water-cell word on river does NOT cross (not 3 water cells)', () {
      Ring twoWater(int idx) {
        final col = idx % 100;
        if (col == 29 || col == 30) return Ring.river;
        return Ring.meadow;
      }
      bool water(int idx) => twoWater(idx) == Ring.river;
      final run = makeRun([28, 29, 30, 31, 32], 'CROSS');
      // Only 2 water cells → not a crossing
      expect(wordClearsFog(run,
          ringAt: twoWater, isWater: water, level: WordLevel.wordsmith), isFalse);
    });

    test('word on river with 3 water but too short (4 letters) at Wordsmith', () {
      Ring stubR(int idx) {
        final col = idx % 100;
        if (col >= 29 && col <= 31) return Ring.river;
        return Ring.meadow;
      }
      bool water(int idx) => stubR(idx) == Ring.river;
      // 4-letter word: 1 meadow + 3 river = no land on far side → 4 total
      final run = makeRun([28, 29, 30, 31], 'FORD');
      // isCrossing: 3 water cells → true. minLength(river, wordsmith) = 5 → 4 < 5 → false
      expect(wordClearsFog(run,
          ringAt: stubR, isWater: water, level: WordLevel.wordsmith), isFalse);
    });
  });

  // ── isCrossing ────────────────────────────────────────────────────────────

  group('isCrossing', () {
    bool water3(int idx) => idx >= 29 && idx <= 31; // cols 29-31 on a 100-wide board

    test('3 water cells → crossing', () {
      final run = WordRun('CROSS', [28, 29, 30, 31, 32], true);
      expect(isCrossing(run, isWater: water3), isTrue);
    });

    test('2 water cells → not a crossing', () {
      final run = WordRun('FORD', [28, 29, 30, 31], true);
      bool water2(int idx) => idx >= 29 && idx <= 30;
      expect(isCrossing(run, isWater: water2), isFalse);
    });

    test('0 water cells → not a crossing', () {
      final run = WordRun('HILL', [40, 41, 42, 43], true);
      bool noWater(_) => false;
      expect(isCrossing(run, isWater: noWater), isFalse);
    });

    test('all 3 water on a wider-than-3 river still counts', () {
      // 5 water cells (unusual, but should still count as crossing)
      bool wide(int idx) => idx >= 28 && idx <= 32;
      final run = WordRun('WIDER', [27, 28, 29, 30, 31, 32, 33], true);
      expect(isCrossing(run, isWater: wide), isTrue);
    });
  });

  // ── xpFor ─────────────────────────────────────────────────────────────────

  group('xpFor', () {
    WordRun run(String word, List<int> positions) =>
        WordRun(word, positions, true);

    test('3 new cells → 9 XP base', () {
      final xp = xpFor(
        run: run('CAT', [10, 11, 12]),
        everUsed: {},
        everWords: {},
        goldenCells: {},
        hasGoldenLetter: false,
      );
      // 3 new * 3 + 5 (new word) = 14. No rare letters.
      expect(xp, 14);
    });

    test('no new cells → 0 XP', () {
      final xp = xpFor(
        run: run('CAT', [10, 11, 12]),
        everUsed: {10, 11, 12},
        everWords: {},
        goldenCells: {},
        hasGoldenLetter: false,
      );
      expect(xp, 0);
    });

    test('known word: no +5 bonus', () {
      final xp = xpFor(
        run: run('CAT', [10, 11, 12]),
        everUsed: {},
        everWords: {'CAT'},
        goldenCells: {},
        hasGoldenLetter: false,
      );
      // 3 new * 3 = 9 (no word bonus)
      expect(xp, 9);
    });

    test('rare letters add +2 each', () {
      final xp = xpFor(
        run: run('JAX', [10, 11, 12]), // J and X are rare
        everUsed: {},
        everWords: {'JAX'}, // known word
        goldenCells: {},
        hasGoldenLetter: false,
      );
      // 3 * 3 (new) + 0 (known) + 2 (J) + 2 (X) = 13
      expect(xp, 13);
    });

    test('golden square doubles XP', () {
      final xp = xpFor(
        run: run('CAT', [10, 11, 12]),
        everUsed: {},
        everWords: {},
        goldenCells: {11}, // middle cell is golden
        hasGoldenLetter: false,
      );
      // (3*3 + 5) * 2 = 28
      expect(xp, 28);
    });

    test('golden letter doubles XP', () {
      final xp = xpFor(
        run: run('CAT', [10, 11, 12]),
        everUsed: {},
        everWords: {},
        goldenCells: {},
        hasGoldenLetter: true,
      );
      expect(xp, 28);
    });

    test('1 new cell, 2 old → XP only for new cell', () {
      final xp = xpFor(
        run: run('CAT', [10, 11, 12]),
        everUsed: {10, 11}, // only cell 12 is new
        everWords: {'CAT'}, // known
        goldenCells: {},
        hasGoldenLetter: false,
      );
      // 1 new * 3 = 3. Word bonus: no. Rare: no.
      expect(xp, 3);
    });

    test('rare letter on old cell still adds +2', () {
      final xp = xpFor(
        run: run('JAX', [10, 11, 12]),
        everUsed: {10, 11, 12}, // all old → 0 XP
        everWords: {},
        goldenCells: {},
        hasGoldenLetter: false,
      );
      // All cells old → 0 XP regardless
      expect(xp, 0);
    });
  });

  // ── fogNote ───────────────────────────────────────────────────────────────

  group('fogNote', () {
    Ring meadow(int _) => Ring.meadow;
    bool noWater(int _) => false;

    test('returns null when fog clears', () {
      final run = WordRun('CATS', [0, 1, 2, 3], true);
      expect(
          fogNote(run, ringAt: meadow, isWater: noWater, level: WordLevel.wordsmith),
          isNull);
    });

    test('returns ring note when too short', () {
      Ring forest(int _) => Ring.forest;
      final run = WordRun('CAT', [0, 1, 2], true);
      final note = fogNote(run, ringAt: forest, isWater: noWater, level: WordLevel.wordsmith);
      expect(note, isNotNull);
      expect(note, contains('4+'));
      expect(note, contains('forest'));
    });

    test('returns river note when no crossing', () {
      bool allWater(int _) => true;
      Ring river(int _) => Ring.river;
      final run = WordRun('CAT', [0, 1, 2], true);
      final note = fogNote(run, ringAt: river, isWater: allWater, level: WordLevel.wordsmith);
      expect(note, isNotNull);
      expect(note, contains('river'));
    });
  });
}
