import 'grid_config.dart';

// Immutable snapshot of one grid game's board/rack/pool. Board and rack are
// kept as separate lists (rather than one combined list with a hardcoded
// split index, as the original single-mode implementation did) so board
// size can vary freely per mode (10x10 for most modes, a larger pannable
// grid for Infinite Estate) without any index-arithmetic assumptions
// leaking into the game logic.
class GridGameState {
  final GridConfig config;
  final List<String?> boardCells;
  final List<String?> rackCells;

  // Remaining draw pool (letters not yet dealt to the rack).
  final List<String> pool;

  // Every letter ever dealt to this game (initial deal + any trade-ins/
  // refills). Used by finite modes to know when "the pool is empty" (every
  // dealt letter is on the board).
  final List<String> dealtLetters;

  // Spec-17 letter bag: letters that are the player's but don't fit the rack
  // (put back from the board, gifts, golden letters). Each rack letter used
  // pulls the next one from here before anything is dealt from the pool.
  final List<String> bag;

  const GridGameState({
    required this.config,
    required this.boardCells,
    required this.rackCells,
    required this.pool,
    required this.dealtLetters,
    this.bag = const [],
  });

  int get filledBoardCount => boardCells.where((c) => c != null).length;

  // True once every letter this game has ever dealt out is placed on the
  // board -- the finite-mode "emptied the pool" win condition.
  bool get isPoolEmptied =>
      dealtLetters.isNotEmpty && filledBoardCount == dealtLetters.length;

  GridGameState copyWith({
    List<String?>? boardCells,
    List<String?>? rackCells,
    List<String>? pool,
    List<String>? dealtLetters,
    List<String>? bag,
  }) {
    return GridGameState(
      config: config,
      boardCells: boardCells ?? this.boardCells,
      rackCells: rackCells ?? this.rackCells,
      pool: pool ?? this.pool,
      dealtLetters: dealtLetters ?? this.dealtLetters,
      bag: bag ?? this.bag,
    );
  }
}
