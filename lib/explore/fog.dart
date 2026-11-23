import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Compact bit-set that tracks which board cells have had their fog cleared.
///
/// 500 × 500 = 250 000 cells → 31 250 bytes.
/// Serialises to a base-64 string for storage in [VillageSaveData].
///
/// Immutable from the outside; modifications return new instances via
/// [clearAround] or use in-place mutations when building (see the factory).
class FogMap {
  final int boardWidth;
  final int boardHeight;

  /// One bit per cell; bit [index] is set when the cell is cleared.
  final Uint8List _bits;

  FogMap._({
    required this.boardWidth,
    required this.boardHeight,
    required Uint8List bits,
  }) : _bits = bits;

  /// Creates an all-fogged map.
  factory FogMap.empty({int boardWidth = 500, int boardHeight = 500}) =>
      FogMap._(
        boardWidth: boardWidth,
        boardHeight: boardHeight,
        bits: Uint8List(boardWidth * boardHeight ~/ 8 + 1),
      );

  /// Deserialises from a base-64 string (produced by [toBase64]).
  factory FogMap.fromBase64(
    String b64, {
    int boardWidth = 500,
    int boardHeight = 500,
  }) {
    final decoded = base64Decode(b64);
    final expected = boardWidth * boardHeight ~/ 8 + 1;
    // Accept a shorter buffer (all extra bits treated as 0 = fogged).
    final bits = Uint8List(expected);
    bits.setRange(0, math.min(decoded.length, expected), decoded);
    return FogMap._(boardWidth: boardWidth, boardHeight: boardHeight, bits: bits);
  }

  /// Serialises to a base-64 string.
  String toBase64() => base64Encode(_bits);

  // ── Bit operations ────────────────────────────────────────────────────────

  void _set(int index) {
    _bits[index >> 3] |= 1 << (index & 7);
  }

  /// Whether cell [index] has been cleared (fog lifted).
  bool isCleared(int index) {
    if (index < 0 || index >= boardWidth * boardHeight) return false;
    return (_bits[index >> 3] >> (index & 7)) & 1 == 1;
  }

  /// Whether cell [index] is visible — cleared itself, or adjacent to a
  /// cleared cell (the one-square "fuzzy edge" a player can drop onto).
  bool canSee(int index) {
    if (isCleared(index)) return true;
    final r = index ~/ boardWidth;
    final c = index % boardWidth;
    // Check the 8 neighbours and the cell itself (already checked above).
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr;
        final nc = c + dc;
        if (nr < 0 || nr >= boardHeight || nc < 0 || nc >= boardWidth) continue;
        if (isCleared(nr * boardWidth + nc)) return true;
      }
    }
    return false;
  }

  // ── Clearing ──────────────────────────────────────────────────────────────

  /// Returns a new [FogMap] with the Chebyshev neighbourhood of every cell
  /// in [cells] cleared (radius squares in each direction).
  FogMap clearAround(List<int> cells, {int radius = 3}) {
    final next = FogMap._(
      boardWidth: boardWidth,
      boardHeight: boardHeight,
      bits: Uint8List.fromList(_bits),
    );
    for (final idx in cells) {
      final row = idx ~/ boardWidth;
      final col = idx % boardWidth;
      final rMin = math.max(0, row - radius);
      final rMax = math.min(boardHeight - 1, row + radius);
      final cMin = math.max(0, col - radius);
      final cMax = math.min(boardWidth - 1, col + radius);
      for (var r = rMin; r <= rMax; r++) {
        for (var c = cMin; c <= cMax; c++) {
          next._set(r * boardWidth + c);
        }
      }
    }
    return next;
  }

  /// A copy with every cleared cell moved by ([dRow], [dCol]); cells that
  /// would land off the board are dropped.
  FogMap shifted(int dRow, int dCol) {
    final next = FogMap.empty(boardWidth: boardWidth, boardHeight: boardHeight);
    final total = boardWidth * boardHeight;
    for (var i = 0; i < total; i++) {
      if (!isCleared(i)) continue;
      final r = i ~/ boardWidth + dRow, c = i % boardWidth + dCol;
      if (r < 0 || c < 0 || r >= boardHeight || c >= boardWidth) continue;
      next._set(r * boardWidth + c);
    }
    return next;
  }

  /// Clears [cells] themselves (without any radius).
  FogMap clearCells(List<int> cells) => clearAround(cells, radius: 0);

  /// How many cells are cleared.
  int get clearedCount {
    var n = 0;
    for (final byte in _bits) {
      // Brian Kernighan's bit-count
      var b = byte;
      while (b != 0) {
        b &= b - 1;
        n++;
      }
    }
    return n;
  }

  /// Fraction of non-coast cells that are cleared (0.0–1.0).
  /// [totalReachable] should be the count of meadow+forest+river+hills+mountains
  /// cells — supply it from [IslandMap] to avoid a full board scan here.
  double exploredFraction(int totalReachable) {
    if (totalReachable == 0) return 0.0;
    return clearedCount / totalReachable;
  }
}
