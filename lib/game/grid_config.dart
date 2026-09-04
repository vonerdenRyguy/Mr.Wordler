// Configuration for one grid-game session. Every mode (Free Play, Time
// Attack, Daily Estate Challenge, Theme Rush, Infinite Estate) builds a
// GridGameController from one of these, so the same controller/board
// widget can back all of them.
class GridConfig {
  final int boardWidth;
  final int boardHeight;
  final int rackSize;

  // Total letters generated for the draw pool (standard Bananagrams uses
  // 144). Only the first `rackSize` are dealt at start; the rest remain in
  // the pool for trade-ins/refills.
  final int totalPoolSize;

  // If set, the letter draw is deterministic for this seed (used by the
  // Daily Estate Challenge so every player gets identical letters on a
  // given date). If null, the draw is freshly randomized each time.
  final int? randomSeed;

  // Infinite Estate: whenever a rack tile is moved onto the board, a new
  // letter is immediately drawn into that rack slot from the pool, so the
  // rack never runs dry. When the pool itself runs out, the slot is left
  // empty until a trade-in returns letters to the pool.
  final bool refillRackOnPlace;

  const GridConfig({
    required this.boardWidth,
    required this.boardHeight,
    required this.rackSize,
    this.totalPoolSize = 144,
    this.randomSeed,
    this.refillRackOnPlace = false,
  });

  int get boardCellCount => boardWidth * boardHeight;
}
