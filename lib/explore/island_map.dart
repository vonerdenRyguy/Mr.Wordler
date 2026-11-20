import 'dart:math' as math;

// ── Enumerations ─────────────────────────────────────────────────────────────

/// Each ring on the island, ordered outward from the village centre.
enum Ring {
  meadow,
  forest,
  river,
  hills,
  mountains,
  coast;

  /// Human-readable name shown on signs.
  String get displayName => switch (this) {
        Ring.meadow => 'Meadow',
        Ring.forest => 'Forest',
        Ring.river => 'River',
        Ring.hills => 'Hills',
        Ring.mountains => 'Mountains',
        Ring.coast => 'Sea',
      };
}

/// A special tile on the island.
enum SpecialKind {
  chest,
  goldenSquare,
  boulder,
  shrine,
  landmark,

  /// A villager waiting to be brought home (spec-16). Their id is `v0`..`v11`.
  villager,
}

/// Which shrine a [SpecialKind.shrine] tile represents.
enum ShrineKind {
  /// Forest shrine — +2 hints per visit.
  sight,

  /// River far-bank shrine — +1 free Swap per visit.
  wind,

  /// Hills shrine — a new music loop.
  songs,

  /// Mountains shrine — +1 rack letter.
  plenty;

  String get displayName => switch (this) {
        ShrineKind.sight => 'Shrine of Sight',
        ShrineKind.wind => 'Shrine of Wind',
        ShrineKind.songs => 'Shrine of Songs',
        ShrineKind.plenty => 'Shrine of Plenty',
      };
}

/// Which landmark a [SpecialKind.landmark] tile represents.
enum LandmarkKind {
  /// Forest landmark.
  giantOak,

  /// River landmark.
  waterfall,

  /// Hills landmark.
  windmill,

  /// Mountains landmark.
  castle;

  String get displayName => switch (this) {
        LandmarkKind.giantOak => 'Giant Oak',
        LandmarkKind.waterfall => 'Waterfall',
        LandmarkKind.windmill => 'Windmill',
        LandmarkKind.castle => 'Castle',
      };
}

// ── SpecialTile ──────────────────────────────────────────────────────────────

/// A single special tile placed on the island map.
class SpecialTile {
  /// Unique identifier (stable across saves for the same seed).
  final String id;
  final SpecialKind kind;

  /// Board cell index (row * boardWidth + col).
  final int cell;

  /// Letter printed on the boulder — non-null only for [SpecialKind.boulder].
  final String? boulderLetter;

  /// Which shrine — non-null only for [SpecialKind.shrine].
  final ShrineKind? shrine;

  /// Which landmark — non-null only for [SpecialKind.landmark].
  final LandmarkKind? landmark;

  const SpecialTile({
    required this.id,
    required this.kind,
    required this.cell,
    this.boulderLetter,
    this.shrine,
    this.landmark,
  });

  @override
  String toString() => 'SpecialTile($id, $kind, cell=$cell)';
}

// ── Ring boundary constants ───────────────────────────────────────────────────

/// Chebyshev distances from the nearest home (inclusive upper bounds).
/// River spans _forestMax+1 .. _riverMax (inclusive), giving a 3-wide moat.
const _meadowMax = 12;
const _forestMax = 28;
const _riverMax = 31; // river = 29..31
const _hillsMax = 50;
const _mountainsMax = 75;

/// Letters available for boulder tiles — common enough to combine into words,
/// rare enough to be an interesting obstacle.
const _boulderLetters = [
  'B', 'C', 'D', 'F', 'G', 'H', 'L', 'M', 'N', 'P', 'R', 'S', 'T', //
];

// ── IslandMap ─────────────────────────────────────────────────────────────────

/// The island's fixed layout: rings and special tiles.
///
/// Pure and seeded — the same [seed] and [homes] always produce the same map,
/// regardless of when or where it is constructed. Ready for spec-17's
/// multi-village island: [homes] accepts more than one home cell.
class IslandMap {
  final int seed;

  /// Board cell indices (row * boardWidth + col) of each village home spot.
  final List<int> homes;

  final int boardWidth;
  final int boardHeight;

  /// Every special tile on the island, in placement order.
  late final List<SpecialTile> specials;

  /// Fast lookup: board cell index → special tile.
  late final Map<int, SpecialTile> _byCell;

  /// Count of non-coast cells (Meadow through Mountains) for explored-fraction.
  late final int reachableCellCount;

  IslandMap({
    required this.seed,
    required this.homes,
    this.boardWidth = 500,
    this.boardHeight = 500,
  }) {
    specials = _generateSpecials();
    _byCell = {for (final s in specials) s.cell: s};
    reachableCellCount = _countReachable();
  }

  int _countReachable() {
    // Count all cells that belong to a non-coast ring.
    if (homes.isEmpty) return 0;
    final homeR = homes.first ~/ boardWidth;
    final homeC = homes.first % boardWidth;
    const maxDist = _mountainsMax;
    var count = 0;
    final r0 = math.max(0, homeR - maxDist);
    final r1 = math.min(boardHeight - 1, homeR + maxDist);
    final c0 = math.max(0, homeC - maxDist);
    final c1 = math.min(boardWidth - 1, homeC + maxDist);
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        if (ringAt(r, c) != Ring.coast) count++;
      }
    }
    return count;
  }

  // ── Ring queries ─────────────────────────────────────────────────────────

  /// Minimum Chebyshev distance from any home to ([row], [col]).
  int _distFromHome(int row, int col) {
    if (homes.isEmpty) return 999;
    var min = 999;
    for (final h in homes) {
      final hr = h ~/ boardWidth;
      final hc = h % boardWidth;
      final d = math.max((row - hr).abs(), (col - hc).abs());
      if (d < min) min = d;
    }
    return min;
  }

  /// The [Ring] that ([row], [col]) belongs to.
  Ring ringAt(int row, int col) {
    if (row < 0 || row >= boardHeight || col < 0 || col >= boardWidth) {
      return Ring.coast;
    }
    final d = _distFromHome(row, col);
    if (d <= _meadowMax) return Ring.meadow;
    if (d <= _forestMax) return Ring.forest;
    if (d <= _riverMax) return Ring.river;
    if (d <= _hillsMax) return Ring.hills;
    if (d <= _mountainsMax) return Ring.mountains;
    return Ring.coast;
  }

  /// The [Ring] that cell [index] belongs to.
  Ring ringAtIndex(int index) =>
      ringAt(index ~/ boardWidth, index % boardWidth);

  /// Whether ([row], [col]) is a water (river-ring) cell.
  bool isWater(int row, int col) => ringAt(row, col) == Ring.river;

  /// Whether cell [index] is a water cell.
  bool isWaterIndex(int index) =>
      ringAt(index ~/ boardWidth, index % boardWidth) == Ring.river;

  /// The special tile at board cell [index], or null if none.
  SpecialTile? specialAt(int index) => _byCell[index];

  // ── Specials generation ──────────────────────────────────────────────────

  List<SpecialTile> _generateSpecials() {
    final rng = math.Random(seed);
    final used = <int>{};
    final result = <SpecialTile>[];
    var counter = 0;

    // ---- helpers ----

    String nextId() => 's${counter++}';

    void placeShrine(Ring ring, ShrineKind kind) {
      final cells = _pickCells(rng, ring, 1, used, waterOk: false);
      for (final c in cells) {
        result.add(SpecialTile(
            id: nextId(), kind: SpecialKind.shrine, cell: c, shrine: kind));
        used.add(c);
      }
    }

    void placeLandmark(Ring ring, LandmarkKind kind) {
      // Waterfall sits in the river itself; all other landmarks avoid water.
      final cells = _pickCells(rng, ring, 1, used, waterOk: ring == Ring.river);
      for (final c in cells) {
        result.add(SpecialTile(
            id: nextId(),
            kind: SpecialKind.landmark,
            cell: c,
            landmark: kind));
        used.add(c);
      }
    }

    void placeChests(Ring ring, int count) {
      final cells = _pickCells(rng, ring, count, used, waterOk: false);
      for (final c in cells) {
        result.add(SpecialTile(id: nextId(), kind: SpecialKind.chest, cell: c));
        used.add(c);
      }
    }

    void placeGolden(Ring ring, int count) {
      final cells = _pickCells(rng, ring, count, used, waterOk: false);
      for (final c in cells) {
        result.add(SpecialTile(
            id: nextId(), kind: SpecialKind.goldenSquare, cell: c));
        used.add(c);
      }
    }

    void placeBoulders(Ring ring, int count) {
      final cells = _pickCells(rng, ring, count, used, waterOk: false);
      for (final c in cells) {
        final letter = _boulderLetters[rng.nextInt(_boulderLetters.length)];
        result.add(SpecialTile(
            id: nextId(),
            kind: SpecialKind.boulder,
            cell: c,
            boulderLetter: letter));
        used.add(c);
      }
    }

    // ---- placement order (matches spec-15 decision 7) ----

    // Meadow — one chest as a first taste.
    placeChests(Ring.meadow, 1);

    // Forest — shrine of Sight, Giant Oak landmark, 4 chests, 6 golden, 3 boulders.
    placeShrine(Ring.forest, ShrineKind.sight);
    placeLandmark(Ring.forest, LandmarkKind.giantOak);
    placeChests(Ring.forest, 4);
    placeGolden(Ring.forest, 6);
    placeBoulders(Ring.forest, 3);

    // River — Waterfall landmark (sits in the water).
    placeLandmark(Ring.river, LandmarkKind.waterfall);

    // Hills — shrine of Wind (far bank, just past the river),
    // shrine of Songs, Windmill, 6 chests (4 normal + 2 "far bank"), 6 golden, 3 boulders.
    placeShrine(Ring.hills, ShrineKind.wind);
    placeShrine(Ring.hills, ShrineKind.songs);
    placeLandmark(Ring.hills, LandmarkKind.windmill);
    placeChests(Ring.hills, 6);
    placeGolden(Ring.hills, 6);
    placeBoulders(Ring.hills, 3);

    // Mountains — shrine of Plenty, Castle, 4 chests, 6 golden, 3 boulders.
    placeShrine(Ring.mountains, ShrineKind.plenty);
    placeLandmark(Ring.mountains, LandmarkKind.castle);
    placeChests(Ring.mountains, 4);
    placeGolden(Ring.mountains, 6);
    placeBoulders(Ring.mountains, 3);

    _placeVillagers(result, used);

    return result;
  }

  /// How many villagers wait on the island (spec-16).
  static const villagerCount = 12;

  /// Villagers per ring: the first stands a few squares from home.
  static const _villagersPerRing = {
    Ring.meadow: 1,
    Ring.forest: 4,
    Ring.hills: 4,
    Ring.mountains: 3,
  };

  /// Adds the 12 villagers after every other special, from their own random
  /// stream, so no earlier chest, shrine or landmark ever moves.
  void _placeVillagers(List<SpecialTile> result, Set<int> used) {
    final rng = math.Random(seed ^ 0x16F);
    var n = 0;
    void add(int cell) {
      result.add(SpecialTile(id: 'v${n++}', kind: SpecialKind.villager, cell: cell));
      used.add(cell);
    }

    // The first one: 4..8 squares from the (first) home, inside the meadow.
    final hr = homes.first ~/ boardWidth, hc = homes.first % boardWidth;
    final near = <int>[];
    for (var r = hr - 8; r <= hr + 8; r++) {
      for (var c = hc - 8; c <= hc + 8; c++) {
        if (r < 0 || c < 0 || r >= boardHeight || c >= boardWidth) continue;
        final d = math.max((r - hr).abs(), (c - hc).abs());
        final cell = r * boardWidth + c;
        if (d >= 4 && !used.contains(cell)) near.add(cell);
      }
    }
    if (near.isNotEmpty) add(near[rng.nextInt(near.length)]);

    for (final entry in _villagersPerRing.entries) {
      if (entry.key == Ring.meadow) continue;
      for (final cell in _pickCells(rng, entry.key, entry.value, used, waterOk: false)) {
        add(cell);
      }
    }
  }

  /// The villager tiles, in id order (the meadow one is first).
  List<SpecialTile> get villagers => [for (final s in specials) if (s.kind == SpecialKind.villager) s];

  // ── Cell selection helpers ───────────────────────────────────────────────

  /// Returns up to [count] non-overlapping cell indices from [ring].
  /// Skips water cells unless [waterOk] is true.
  /// Cells already in [used] are excluded from the result (not from [used]).
  List<int> _pickCells(
    math.Random rng,
    Ring ring,
    int count,
    Set<int> used, {
    required bool waterOk,
  }) {
    final candidates = _cellsInRing(ring, waterOk: waterOk);
    // Fisher-Yates shuffle drawing from the shared RNG so placement is
    // globally deterministic.
    for (var i = candidates.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = candidates[i];
      candidates[i] = candidates[j];
      candidates[j] = tmp;
    }
    final picks = <int>[];
    for (final c in candidates) {
      if (picks.length >= count) break;
      if (!used.contains(c)) picks.add(c);
    }
    return picks;
  }

  /// All cells in [ring], scanning just the ring's bounding box.
  /// Optionally excludes water cells.
  List<int> _cellsInRing(Ring ring, {required bool waterOk}) {
    final (minR, maxR, minC, maxC) = _ringBounds(ring);
    final result = <int>[];
    for (var r = minR; r <= maxR; r++) {
      for (var c = minC; c <= maxC; c++) {
        if (ringAt(r, c) != ring) continue;
        if (!waterOk && isWater(r, c)) continue;
        result.add(r * boardWidth + c);
      }
    }
    return result;
  }

  /// Tight bounding box that contains all cells of [ring].
  (int, int, int, int) _ringBounds(Ring ring) {
    if (homes.isEmpty) {
      return (0, boardHeight - 1, 0, boardWidth - 1);
    }
    // For multi-village (spec-17), the union of all homes' bounding boxes.
    var minR = boardHeight - 1;
    var maxR = 0;
    var minC = boardWidth - 1;
    var maxC = 0;
    final maxDist = switch (ring) {
      Ring.meadow => _meadowMax,
      Ring.forest => _forestMax,
      Ring.river => _riverMax,
      Ring.hills => _hillsMax,
      Ring.mountains => _mountainsMax,
      Ring.coast => math.max(boardWidth, boardHeight),
    };
    for (final h in homes) {
      final hr = h ~/ boardWidth;
      final hc = h % boardWidth;
      minR = math.min(minR, math.max(0, hr - maxDist));
      maxR = math.max(maxR, math.min(boardHeight - 1, hr + maxDist));
      minC = math.min(minC, math.max(0, hc - maxDist));
      maxC = math.max(maxC, math.min(boardWidth - 1, hc + maxDist));
    }
    return (minR, maxR, minC, maxC);
  }
}
