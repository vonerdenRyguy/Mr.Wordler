import '../explore/island_map.dart';
import '../game/word_runs.dart';
import '../settings/word_level.dart';

// ── Minimum word lengths by ring and level ────────────────────────────────────

/// Minimum word length required to clear fog in [ring] at [level].
///
/// A word that touches several rings must satisfy every ring's minimum; the
/// river has an additional crossing requirement checked by [isCrossing].
int minLength(Ring ring, WordLevel level) => switch (ring) {
      Ring.meadow => 3,
      Ring.forest => level == WordLevel.sprout ? 3 : 4,
      Ring.river => switch (level) {
          WordLevel.sprout => 4,
          WordLevel.explorer => 4,
          WordLevel.builder => 5,
          WordLevel.wordsmith => 5,
        },
      Ring.hills => switch (level) {
          WordLevel.sprout => 4,
          WordLevel.explorer => 5,
          WordLevel.builder => 6,
          WordLevel.wordsmith => 6,
        },
      Ring.mountains => switch (level) {
          WordLevel.sprout => 4,
          WordLevel.explorer => 5,
          WordLevel.builder => 6,
          WordLevel.wordsmith => 7,
        },
      Ring.coast => 999, // can't clear coast
    };

// ── Fog clearing ─────────────────────────────────────────────────────────────

/// How many cells to clear around each letter, by level.
int clearRadius(WordLevel level) => level == WordLevel.sprout ? 4 : 3;

/// Whether placing [run] should clear fog.
///
/// A word clears fog when:
///   1. It is long enough for every non-coast, non-water ring it touches.
///   2. If it has any water cells, it is a valid [isCrossing] AND long enough
///      for the river ring minimum.
///
/// [ringAt] maps a board cell index to its [Ring].
/// [isWater] returns true for river cells.
bool wordClearsFog(
  WordRun run, {
  required Ring Function(int) ringAt,
  required bool Function(int) isWater,
  required WordLevel level,
}) {
  final len = run.word.length;
  var hasWater = false;

  for (final pos in run.positions) {
    final ring = ringAt(pos);
    if (ring == Ring.coast) return false; // can't clear coast; shouldn't happen
    if (isWater(pos)) {
      hasWater = true;
      continue; // river handled separately
    }
    if (len < minLength(ring, level)) return false;
  }

  if (hasWater) {
    if (!isCrossing(run, isWater: isWater)) return false;
    if (len < minLength(Ring.river, level)) return false;
  }

  return true;
}

// ── River crossing ────────────────────────────────────────────────────────────

/// Whether [run] is a valid river crossing — it contains at least 3 water
/// cells (the full width of the river along any cardinal axis).
///
/// River cells in a straight horizontal or vertical line are always exactly
/// 3 (Chebyshev distances 29, 30, 31 from home). A word that covers all 3
/// is a crossing; one that stops short is not.
bool isCrossing(WordRun run, {required bool Function(int) isWater}) {
  final waterCount = run.positions.where(isWater).length;
  return waterCount >= 3;
}

// ── XP calculation ────────────────────────────────────────────────────────────

/// Rare letters that each contribute +2 XP.
const _rareLetters = {'J', 'K', 'Q', 'V', 'X', 'Z'};

/// XP earned for placing [run].
///
/// Returns 0 if no cell in [run] is new (all positions already in [everUsed]).
///
/// Rules (spec-15):
///   • 3 XP per letter on a never-used square.
///   • +5 if [run.word] has never been spelled before (not in [everWords]).
///   • +2 for each J, K, Q, V, X, Z in the word (regardless of new/old square).
///   • The total is doubled when any run cell overlaps a golden square OR
///     [hasGoldenLetter] is true.
///
/// [everUsed] — board cell indices that have ever held a letter.
/// [everWords] — words the player has ever placed.
/// [goldenCells] — board cell indices that are golden squares.
/// [hasGoldenLetter] — the placed word used a golden letter tile.
int xpFor({
  required WordRun run,
  required Set<int> everUsed,
  required Set<String> everWords,
  required Set<int> goldenCells,
  required bool hasGoldenLetter,
}) {
  // Count new cells (cells not previously used).
  final newCells =
      run.positions.where((p) => !everUsed.contains(p)).length;
  if (newCells == 0) return 0; // no XP for all-used squares

  var xp = newCells * 3;

  // Word discovery bonus.
  if (!everWords.contains(run.word)) xp += 5;

  // Rare-letter bonus.
  for (final letter in run.word.split('')) {
    if (_rareLetters.contains(letter)) xp += 2;
  }

  // Golden multiplier (any golden square in the run, or a golden tile used).
  final onGolden = run.positions.any((p) => goldenCells.contains(p));
  if (onGolden || hasGoldenLetter) xp *= 2;

  return xp;
}

// ── Notes for the UI ──────────────────────────────────────────────────────────

/// A human-readable note explaining why [run] did not clear fog.
/// Returns null when fog does clear (no note needed).
String? fogNote(
  WordRun run, {
  required Ring Function(int) ringAt,
  required bool Function(int) isWater,
  required WordLevel level,
}) {
  final len = run.word.length;
  var hasWater = false;
  Ring? strictestRing;

  for (final pos in run.positions) {
    final ring = ringAt(pos);
    if (isWater(pos)) {
      hasWater = true;
      continue;
    }
    final needed = minLength(ring, level);
    if (len < needed) {
      // Record the strictest (highest minimum) ring.
      if (strictestRing == null ||
          minLength(ring, level) > minLength(strictestRing, level)) {
        strictestRing = ring;
      }
    }
  }

  if (hasWater && !isCrossing(run, isWater: isWater)) {
    return 'Spell across the river with ${minLength(Ring.river, level)}+ letters.';
  }

  if (strictestRing != null) {
    return 'The ${strictestRing.displayName.toLowerCase()} needs '
        '${minLength(strictestRing, level)}+ letters to clear the fog.';
  }

  if (hasWater && len < minLength(Ring.river, level)) {
    return 'Spell across the river with ${minLength(Ring.river, level)}+ letters.';
  }

  return null; // fog clears — no note
}
