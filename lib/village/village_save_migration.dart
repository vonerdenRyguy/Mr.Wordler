import '../explore/fog.dart';
import 'village_save.dart';

/// Brings an older save up to the current format.
///
/// Version 1 → 2: the rack shrinks to [rackSize]. The first [rackSize]
/// letters (in slot order, skipping empties) stay in the rack; the rest
/// go back to the pool and leave dealtLetters. Board, pool order of
/// existing letters, landmarks, discovered words and lastCashedOutScore
/// are untouched.
///
/// Version 2 → 3 (spec-15): fog and explore state are initialised.
///   - [boardWidth] / [boardHeight]: board dimensions (default 500×500).
///   - [homeIndex]: board cell index of the village home spot (default
///     board centre). Used to compute which cells get pre-cleared.
///   - Fog is cleared in a Chebyshev-3 ring around every existing board
///     letter (the standard radius; not level-dependent on migration).
///   - [everUsed] is seeded from every currently occupied board cell.
///   - [foundSpecials], [shrines], [levelTreats] start empty; the
///     explore controller rewards specials already under old letters on
///     the first scan after migration.
///
/// Version 3 → 4 (spec-16): an empty villager book.
///
/// Version 4 → 5 (spec-17): only the version changes here. The village
/// screen does the one-time tidy of loose letters (it has the dictionary)
/// and records it as `tidiedLoose`.
VillageSaveData migrateVillageSave(
  VillageSaveData data, {
  required int rackSize,
  int boardWidth = 500,
  int boardHeight = 500,
  int? homeIndex,
}) {
  // ── v1 → v2 ─────────────────────────────────────────────────────────────
  if (data.saveVersion < 2) {
    final letters = data.rackCells.whereType<String>().toList();
    final kept = letters.take(rackSize).toList();
    final returned = letters.skip(rackSize).toList();

    final rack = <String?>[...kept, ...List<String?>.filled(rackSize - kept.length, null)];
    final dealt = List<String>.from(data.dealtLetters);
    for (final letter in returned) {
      dealt.remove(letter);
    }

    data = VillageSaveData(
      boardCells: data.boardCells,
      rackCells: rack,
      pool: [...data.pool, ...returned],
      dealtLetters: dealt,
      lastCashedOutScore: data.lastCashedOutScore,
      reachedLandmarks: data.reachedLandmarks,
      discoveredWords: data.discoveredWords,
      saveVersion: 2,
    );
  }

  // ── v2 → v3 ─────────────────────────────────────────────────────────────
  if (data.saveVersion < 3) {
    // Collect every occupied board cell.
    final occupiedCells = <int>[];
    for (var i = 0; i < data.boardCells.length; i++) {
      if (data.boardCells[i] != null) occupiedCells.add(i);
    }

    // Clear fog in a Chebyshev-3 radius around each occupied cell (the
    // non-Sprout default; we don't know the level at migration time).
    final fog = FogMap.empty(boardWidth: boardWidth, boardHeight: boardHeight)
        .clearAround(occupiedCells, radius: kClearRadiusMigration);

    data = VillageSaveData(
      boardCells: data.boardCells,
      rackCells: data.rackCells,
      pool: data.pool,
      dealtLetters: data.dealtLetters,
      lastCashedOutScore: data.lastCashedOutScore,
      reachedLandmarks: data.reachedLandmarks,
      discoveredWords: data.discoveredWords,
      saveVersion: 3,
      mapSeed: VillageSaveData.kDefaultMapSeed,
      mapVersion: VillageSaveData.kDefaultMapVersion,
      cleared: fog.toBase64(),
      everUsed: occupiedCells.toSet(),
      foundSpecials: const {},
      shrines: const {},
      levelTreats: const {},
    );
  }

  // ── v3 → v4 (spec-16) ───────────────────────────────────────────────────
  // Villagers start as an empty book; nothing else changes. A villager whose
  // square already holds a word joins on the village screen's first scan.
  if (data.saveVersion < 4) {
    data = data.copyWith(saveVersion: 4);
  }

  // ── v4 → v5 (spec-17) ───────────────────────────────────────────────────────────────────────
  if (data.saveVersion < 5) {
    data = data.copyWith(saveVersion: 5);
  }

  return data;
}

/// Fixed radius used when initialising fog from an existing v2 save.
/// Does not depend on the player's level (which is unknown at migration time).
const kClearRadiusMigration = 3;
