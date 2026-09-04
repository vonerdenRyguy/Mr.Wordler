import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart';
import 'grid_config.dart';
import 'grid_game_state.dart';
import 'tile_location.dart';

// Shared game logic for every grid-based mode (Free Play, Time Attack,
// Daily Estate Challenge, Theme Rush, Infinite Estate). Holds no
// BuildContext/UI state -- just the board/rack/pool and the operations a
// player can perform on them. UI-specific behavior (timers, win/lose
// screens, rewards) lives in each mode's screen, built on top of this.
class GridGameController extends StateNotifier<GridGameState> {
  GridGameController(GridConfig config) : super(_initialState(config));

  final WordValidator _validator = WordValidator();

  static GridGameState _initialState(GridConfig config) {
    final pool = LetterGenerator.generateLetters(
      config.totalPoolSize,
      seed: config.randomSeed,
    );
    final dealt = pool.sublist(0, config.rackSize);
    final remainingPool = pool.sublist(config.rackSize);

    return GridGameState(
      config: config,
      boardCells: List<String?>.filled(config.boardCellCount, null),
      rackCells: List<String?>.from(dealt),
      pool: remainingPool,
      dealtLetters: List<String>.from(dealt),
    );
  }

  List<String?> _cellsFor(TileZone zone) =>
      zone == TileZone.board ? state.boardCells : state.rackCells;

  static const _vowels = {'A', 'E', 'I', 'O', 'U'};

  // Moves a tile from one slot to another (board<->board, rack<->rack, or
  // board<->rack). No-ops if `from` is empty or `to` is already occupied.
  //
  // `preferBalancedRefill` (used by Infinite Estate/Village's Farm
  // structure ability, off by default/for every other mode) only affects
  // the auto-refill-on-place behavior below: instead of a uniformly
  // random draw, it prefers whichever of vowel/consonant the rack (after
  // this move) has fewer of, falling back to a random draw if the pool
  // has none of that type. Purely a nicer distribution, never a worse one
  // -- an unlucky player never ends up worse off than the random draw
  // would have left them.
  void moveTile(TileLocation from, TileLocation to, {bool preferBalancedRefill = false}) {
    final fromCells = List<String?>.from(_cellsFor(from.zone));
    final letter = fromCells[from.index];
    if (letter == null) return;

    final sameZone = from.zone == to.zone;
    final toCells = sameZone ? fromCells : List<String?>.from(_cellsFor(to.zone));
    if (toCells[to.index] != null) return;

    fromCells[from.index] = null;
    toCells[to.index] = letter;

    List<String?> board = state.boardCells;
    List<String?> rack = state.rackCells;
    if (from.zone == TileZone.board) board = fromCells;
    if (from.zone == TileZone.rack) rack = fromCells;
    if (to.zone == TileZone.board) board = toCells;
    if (to.zone == TileZone.rack) rack = toCells;

    // Infinite Estate: refilling a rack slot the instant its tile leaves
    // for the board keeps the rack at a constant size forever.
    if (state.config.refillRackOnPlace &&
        from.zone == TileZone.rack &&
        to.zone == TileZone.board &&
        state.pool.isNotEmpty) {
      final newPool = List<String>.from(state.pool);
      final drawn = preferBalancedRefill ? _drawBalancedLetter(newPool, rack) : _drawRandomLetter(newPool);
      rack = List<String?>.from(rack);
      rack[from.index] = drawn;
      state = state.copyWith(
        boardCells: board,
        rackCells: rack,
        pool: newPool,
        dealtLetters: [...state.dealtLetters, drawn],
      );
      return;
    }

    state = state.copyWith(boardCells: board, rackCells: rack);
  }

  // Mutates `pool` (removing the drawn letter) and returns it.
  String _drawRandomLetter(List<String> pool) {
    pool.shuffle();
    return pool.removeLast();
  }

  String _drawBalancedLetter(List<String> pool, List<String?> currentRack) {
    final vowelCount = currentRack.where((c) => c != null && _vowels.contains(c)).length;
    final consonantCount = currentRack.where((c) => c != null && !_vowels.contains(c)).length;
    final wantVowel = vowelCount < consonantCount;

    pool.shuffle();
    final matchIndex = pool.indexWhere((letter) => _vowels.contains(letter) == wantVowel);
    if (matchIndex != -1) {
      return pool.removeAt(matchIndex);
    }
    // Pool has none of the preferred type right now -- fall back to a
    // normal random draw rather than leaving the rack slot empty.
    return pool.removeLast();
  }

  // Trades one rack tile back into the pool for 3 fresh ones (classic
  // Bananagrams "dump"). Returns false (and changes nothing) if there
  // aren't at least 3 open rack slots to receive the new letters, matching
  // the original single-mode rule.
  bool tradeIn(int rackIndex) {
    final letter = state.rackCells[rackIndex];
    if (letter == null) return false;

    final rack = List<String?>.from(state.rackCells);
    rack[rackIndex] = null;
    final openSlots = rack.where((c) => c == null).length;
    if (openSlots < 3) return false;

    final pool = List<String>.from(state.pool)..add(letter);
    pool.shuffle();

    final dealt = List<String>.from(state.dealtLetters)..remove(letter);

    final newLetters = <String>[];
    for (int i = 0; i < 3 && pool.isNotEmpty; i++) {
      newLetters.add(pool.removeLast());
    }
    final emptyIndices = [
      for (int i = 0; i < rack.length; i++)
        if (rack[i] == null) i,
    ];
    for (int i = 0; i < newLetters.length && i < emptyIndices.length; i++) {
      rack[emptyIndices[i]] = newLetters[i];
    }
    dealt.addAll(newLetters);

    state = state.copyWith(rackCells: rack, pool: pool, dealtLetters: dealt);
    return true;
  }

  // Draws one extra letter from the pool directly into the first empty
  // rack slot -- a pure bonus, no cost. A no-op (never a penalty) if the
  // pool is empty or the rack has no open slot. Generic, not landmark-
  // specific: any mode/event that wants to hand the player a free letter
  // can use this.
  void drawBonusLetter() {
    if (state.pool.isEmpty) return;
    final emptyIndex = state.rackCells.indexWhere((c) => c == null);
    if (emptyIndex == -1) return;

    final pool = List<String>.from(state.pool)..shuffle();
    final drawn = pool.removeLast();
    final rack = List<String?>.from(state.rackCells);
    rack[emptyIndex] = drawn;

    state = state.copyWith(
      rackCells: rack,
      pool: pool,
      dealtLetters: [...state.dealtLetters, drawn],
    );
  }

  // Replaces the current board/rack/pool wholesale, e.g. to resume a
  // previously-saved session (Infinite Estate's persisted village).
  // Ignored (no-op) if the saved shapes don't match this controller's
  // config -- e.g. an old save from before a board-size change -- so a
  // stale save can't corrupt a fresh session; the caller should treat a
  // no-op as "nothing to restore" and fall back to a fresh board.
  void restoreState({
    required List<String?> boardCells,
    required List<String?> rackCells,
    required List<String> pool,
    required List<String> dealtLetters,
  }) {
    if (boardCells.length != state.config.boardCellCount) return;
    if (rackCells.length != state.config.rackSize) return;
    state = state.copyWith(
      boardCells: boardCells,
      rackCells: rackCells,
      pool: pool,
      dealtLetters: dealtLetters,
    );
  }

  Future<WordCheckResult> checkWords() {
    return _validator.findValidWords(
      state.boardCells,
      state.config.boardWidth,
      state.config.boardHeight,
    );
  }

  // Every valid word currently on the board, freshly re-scanned, mapped to
  // its tile positions. Generic (no notion of "magic words" -- that's a
  // Village-specific concept layered on top by callers, e.g.
  // lib/village/, so the shared engine stays mode-agnostic).
  Future<Map<String, Set<int>>> currentWordPositions() async {
    await _validator.findValidWords(
      state.boardCells,
      state.config.boardWidth,
      state.config.boardHeight,
    );
    return _validator.validWordPositions;
  }

  // The valid dictionary word (if any) currently occupying board index
  // `boardIndex`, freshly re-scanned. Used for tap-for-definition -- a
  // long-press only shows a definition for a word that's actually validly
  // formed right now, not stale from an earlier Check.
  Future<String?> validWordAtBoardIndex(int boardIndex) async {
    await _validator.findValidWords(
      state.boardCells,
      state.config.boardWidth,
      state.config.boardHeight,
    );
    return _validator.validWordContaining(boardIndex);
  }
}
