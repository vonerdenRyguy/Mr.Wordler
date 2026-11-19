// Tests for IslandMap — ring layout, water cells, and special tile placement.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/island_map.dart';

void main() {
  // ── helpers ──────────────────────────────────────────────────────────────

  /// Board size used throughout these tests (matches the real village).
  const bw = 500;
  const bh = 500;

  /// Home at the board centre.
  const centreHome = (bh ~/ 2) * bw + (bw ~/ 2); // 250 * 500 + 250 = 125250

  /// Build a standard centred map with the given seed.
  IslandMap mapFor(int seed) =>
      IslandMap(seed: seed, homes: [centreHome], boardWidth: bw, boardHeight: bh);

  // ── determinism ──────────────────────────────────────────────────────────

  test('same seed → same map every time', () {
    final a = mapFor(42);
    final b = mapFor(42);
    expect(a.specials.length, b.specials.length);
    for (var i = 0; i < a.specials.length; i++) {
      expect(a.specials[i].cell, b.specials[i].cell,
          reason: 'specials[$i].cell differs');
      expect(a.specials[i].kind, b.specials[i].kind,
          reason: 'specials[$i].kind differs');
    }
  });

  test('different seeds → different maps', () {
    final a = mapFor(1);
    final b = mapFor(99999);
    // Extremely unlikely all cells match by chance.
    final cellsA = a.specials.map((s) => s.cell).toSet();
    final cellsB = b.specials.map((s) => s.cell).toSet();
    expect(cellsA, isNot(equals(cellsB)));
  });

  // ── ring boundaries ──────────────────────────────────────────────────────

  test('home cell is meadow', () {
    final map = mapFor(1);
    expect(map.ringAtIndex(centreHome), Ring.meadow);
  });

  test('cells at Chebyshev distances cover all ring types', () {
    final map = mapFor(1);
    const hRow = 250, hCol = 250;

    // Meadow (0–12)
    expect(map.ringAt(hRow, hCol + 12), Ring.meadow);
    expect(map.ringAt(hRow, hCol + 1), Ring.meadow);

    // Forest (13–28)
    expect(map.ringAt(hRow, hCol + 13), Ring.forest);
    expect(map.ringAt(hRow, hCol + 28), Ring.forest);

    // River (29–31)
    expect(map.ringAt(hRow, hCol + 29), Ring.river);
    expect(map.ringAt(hRow, hCol + 30), Ring.river);
    expect(map.ringAt(hRow, hCol + 31), Ring.river);

    // Hills (32–50)
    expect(map.ringAt(hRow, hCol + 32), Ring.hills);
    expect(map.ringAt(hRow, hCol + 50), Ring.hills);

    // Mountains (51–75)
    expect(map.ringAt(hRow, hCol + 51), Ring.mountains);
    expect(map.ringAt(hRow, hCol + 75), Ring.mountains);

    // Coast (> 75)
    expect(map.ringAt(hRow, hCol + 76), Ring.coast);
    expect(map.ringAt(hRow, hCol + 100), Ring.coast);
  });

  test('cells off the board return coast', () {
    final map = mapFor(1);
    expect(map.ringAt(-1, 0), Ring.coast);
    expect(map.ringAt(0, -1), Ring.coast);
    expect(map.ringAt(bh, 0), Ring.coast);
    expect(map.ringAt(0, bw), Ring.coast);
  });

  // ── river ────────────────────────────────────────────────────────────────

  test('river is exactly 3 cells wide along each cardinal axis', () {
    final map = mapFor(1);
    const hRow = 250, hCol = 250;

    // East crossing: columns 219..221 should all be river (distances 31, 30, 29)
    for (final col in [hCol + 29, hCol + 30, hCol + 31]) {
      expect(map.isWater(hRow, col), isTrue,
          reason: 'col=$col should be river');
    }
    // Boundaries: 28 (forest) and 32 (hills) are not water
    expect(map.isWater(hRow, hCol + 28), isFalse);
    expect(map.isWater(hRow, hCol + 32), isFalse);

    // North crossing (same logic, row axis)
    for (final row in [hRow - 29, hRow - 30, hRow - 31]) {
      expect(map.isWater(row, hCol), isTrue,
          reason: 'row=$row should be river');
    }
    expect(map.isWater(hRow - 28, hCol), isFalse);
    expect(map.isWater(hRow - 32, hCol), isFalse);
  });

  test('isWaterIndex agrees with isWater', () {
    final map = mapFor(1);
    const r = 250, c = 282; // river cell: dist = 32? wait — 282-250=32 → hills
    // Use a known river cell
    const riverCol = 250 + 30; // distance 30 → river
    final idx = r * bw + riverCol;
    expect(map.isWaterIndex(idx), equals(map.isWater(r, riverCol)));
  });

  // ── special tile placement ────────────────────────────────────────────────

  test('no two specials share a cell', () {
    final map = mapFor(42);
    final cells = map.specials.map((s) => s.cell).toList();
    expect(cells.toSet().length, cells.length,
        reason: 'duplicate cells found');
  });

  test('every special sits in its expected ring', () {
    final map = mapFor(42);
    for (final s in map.specials) {
      final ring = map.ringAtIndex(s.cell);
      switch (s.kind) {
        case SpecialKind.chest:
        case SpecialKind.goldenSquare:
        case SpecialKind.boulder:
          // Chests/golden/boulders can be in meadow, forest, hills or mountains
          // (never coast; boulders/golden not in river)
          expect(ring, isNot(Ring.coast),
              reason: 'special $s should not be in coast');
          expect(ring, isNot(Ring.river),
              reason: 'chest/golden/boulder $s should not be in river');
        case SpecialKind.shrine:
          expect(
              [Ring.forest, Ring.hills, Ring.mountains].contains(ring), isTrue,
              reason: 'shrine $s should be in forest, hills, or mountains');
        case SpecialKind.landmark:
          // Waterfall is in the river; others are in their ring
          if (s.landmark == LandmarkKind.waterfall) {
            expect(ring, Ring.river,
                reason: 'waterfall should be in river ring');
          } else {
            expect(ring, isNot(Ring.coast));
            expect(ring, isNot(Ring.meadow));
          }
      }
    }
  });

  test('meadow has exactly 1 chest and no other specials', () {
    final map = mapFor(42);
    final meadowSpecials =
        map.specials.where((s) => map.ringAtIndex(s.cell) == Ring.meadow);
    expect(meadowSpecials.length, 1);
    expect(meadowSpecials.single.kind, SpecialKind.chest);
  });

  test('river has exactly 1 special (the waterfall landmark)', () {
    final map = mapFor(42);
    final riverSpecials =
        map.specials.where((s) => map.ringAtIndex(s.cell) == Ring.river).toList();
    expect(riverSpecials.length, 1);
    expect(riverSpecials.single.kind, SpecialKind.landmark);
    expect(riverSpecials.single.landmark, LandmarkKind.waterfall);
  });

  test('special counts match spec', () {
    final map = mapFor(42);

    int countKind(SpecialKind kind) =>
        map.specials.where((s) => s.kind == kind).length;
    int countLandmark(LandmarkKind l) =>
        map.specials.where((s) => s.landmark == l).length;
    int countShrine(ShrineKind sh) =>
        map.specials.where((s) => s.shrine == sh).length;

    // Chests: 1 meadow + 4 forest + 6 hills + 4 mountains = 15
    expect(countKind(SpecialKind.chest), 15);

    // Golden squares: 6 forest + 6 hills + 6 mountains = 18
    expect(countKind(SpecialKind.goldenSquare), 18);

    // Boulders: 3 forest + 3 hills + 3 mountains = 9
    expect(countKind(SpecialKind.boulder), 9);

    // Shrines: Sight, Wind, Songs, Plenty = 4
    expect(countKind(SpecialKind.shrine), 4);
    expect(countShrine(ShrineKind.sight), 1);
    expect(countShrine(ShrineKind.wind), 1);
    expect(countShrine(ShrineKind.songs), 1);
    expect(countShrine(ShrineKind.plenty), 1);

    // Landmarks: 4
    expect(countKind(SpecialKind.landmark), 4);
    expect(countLandmark(LandmarkKind.giantOak), 1);
    expect(countLandmark(LandmarkKind.waterfall), 1);
    expect(countLandmark(LandmarkKind.windmill), 1);
    expect(countLandmark(LandmarkKind.castle), 1);
  });

  test('boulders have a letter', () {
    final map = mapFor(42);
    for (final s in map.specials.where((s) => s.kind == SpecialKind.boulder)) {
      expect(s.boulderLetter, isNotNull,
          reason: 'boulder $s is missing a letter');
      expect(s.boulderLetter!.length, 1);
      expect(s.boulderLetter!, matches(RegExp(r'^[A-Z]$')));
    }
  });

  test('specialAt returns the right tile', () {
    final map = mapFor(42);
    for (final s in map.specials) {
      expect(map.specialAt(s.cell), s);
    }
    // A cell known to have no special (home cell is in meadow, home has no special)
    expect(map.specialAt(centreHome), isNull);
  });

  // ── ringDisplayName ───────────────────────────────────────────────────────

  test('Ring displayName is non-empty for all values', () {
    for (final ring in Ring.values) {
      expect(ring.displayName, isNotEmpty);
    }
  });

  // ── small board (edge cases) ─────────────────────────────────────────────

  test('IslandMap works on a tiny board where most rings are coast', () {
    // 60x60 board, home at centre (30, 30).
    // Max Chebyshev distance from centre to any corner: 30 → river ring.
    // Mountains (51-75) and coast (>75) don't exist on this board.
    final small = IslandMap(
        seed: 7, homes: [30 * 60 + 30], boardWidth: 60, boardHeight: 60);
    // Centre is meadow
    expect(small.ringAt(30, 30), Ring.meadow);
    // Corner (0,0): Chebyshev distance = max(30,30) = 30 → river
    expect(small.ringAt(0, 0), Ring.river);
    // Distance 32 would be hills but (30,30) ± 32 is off the board, so
    // ringAt clips and returns coast via the bounds check.
    expect(small.ringAt(-2, 30), Ring.coast);
    // Specials that fall in missing rings just won't be placed — no crash.
    expect(small.specials, isNotEmpty);
    // No duplicates
    final cells = small.specials.map((s) => s.cell).toList();
    expect(cells.toSet().length, cells.length);
  });
}
