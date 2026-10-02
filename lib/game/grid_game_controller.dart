import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart';
import 'balanced_draw.dart';
import 'grid_config.dart';
import 'grid_game_state.dart';
import 'tile_location.dart';

// Shared game logic for every grid-based mode (Free Play, Time Attack,
// Daily Estate Challenge, Theme Rush, Infinite Estate). Holds no
// BuildContext/UI state -- just the board/rack/pool and the operations a
// player can perform on them. UI-specific behavior (timers, win/lose
// screens, rewards) lives in each mode's screen, built on top of this.
class GridGameController extends StateNotifier<GridGameState> {
  GridGameController(GridConfig config, {Random? random})
      : _random = random ?? Random(),
        super(_initialState(config));

  final WordValidator _validator = WordValidator();
  final Random _random;

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

  // Moves a tile from one slot to another (board<->board, rack<->rack, or
  // board<->rack). No-ops if `from` is empty or `to` is already occupied.
  void moveTile(TileLocation from, TileLocation to) {
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
    // for the board keeps the rack at a constant size forever. Bonus slots
    // (index >= rackSize, see drawBonusLetter) are the exception: a bonus
    // letter is one extra letter, not a permanently bigger rack, so its
    // slot is never refilled -- it just goes away once it's empty.
    if (state.config.refillRackOnPlace &&
        from.zone == TileZone.rack &&
        to.zone == TileZone.board &&
        from.index < state.config.rackSize &&
        state.pool.isNotEmpty) {
      final newPool = List<String>.from(state.pool);
      // `rack` still has this slot empty, which is exactly what
      // drawBalanced expects.
      final drawn = _drawRefill(newPool, rack);
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

    state = state.copyWith(boardCells: board, rackCells: _trimEmptyBonusSlots(rack));
  }

  // Drops empty bonus slots (index >= rackSize) off the end of the rack,
  // so a used-up bonus letter's slot disappears instead of lingering as a
  // permanently empty gap. Only trailing slots are removed, so no other
  // tile's index ever shifts.
  List<String?> _trimEmptyBonusSlots(List<String?> rack) {
    final base = state.config.rackSize;
    if (rack.length <= base || rack.last != null) return rack;
    final trimmed = List<String?>.from(rack);
    while (trimmed.length > base && trimmed.last == null) {
      trimmed.removeLast();
    }
    return trimmed;
  }

  // Mutates `pool` (removing the drawn letter) and returns it.
  String _drawRandomLetter(List<String> pool) {
    pool.shuffle();
    return pool.removeLast();
  }

  // One refill draw for a rack slot. `rack` must have that slot empty.
  String _drawRefill(List<String> pool, List<String?> rack) =>
      state.config.balancedRefill ? drawBalanced(pool, rack, _random) : _drawRandomLetter(pool);

  // Infinite Estate's "Swap letters": every base rack slot (index <
  // rackSize) holding a letter and not in `keepIndices` (the player's
  // pins) goes back to the pool, and is refilled one at a time. Bonus
  // slots are left alone. New letters are drawn before the old ones go
  // back into the pool, so a swap never just hands back what it took
  // (unless the pool would otherwise run dry). Returns false, changing
  // nothing, if the pool is empty or there's nothing to swap. Paying for
  // it is the caller's job, and only after this returns true.
  bool swapRack({required Set<int> keepIndices}) {
    if (state.pool.isEmpty) return false;
    final base = state.config.rackSize;
    final rack = List<String?>.from(state.rackCells);
    final swapIndices = [
      for (int i = 0; i < base && i < rack.length; i++)
        if (rack[i] != null && !keepIndices.contains(i)) i,
    ];
    if (swapIndices.isEmpty) return false;

    final returned = <String>[];
    for (final i in swapIndices) {
      returned.add(rack[i]!);
      rack[i] = null;
    }
    final dealt = List<String>.from(state.dealtLetters);
    for (final letter in returned) {
      dealt.remove(letter);
    }

    final pool = List<String>.from(state.pool);
    for (final i in swapIndices) {
      if (pool.isEmpty) {
        pool.addAll(returned);
        returned.clear();
      }
      final drawn = _drawRefill(pool, rack);
      rack[i] = drawn;
      dealt.add(drawn);
    }
    pool.addAll(returned);

    state = state.copyWith(rackCells: rack, pool: pool, dealtLetters: dealt);
    return true;
  }

  // Fills any empty base rack slot (index < rackSize) from the pool, e.g.
  // right after a migrated save that held fewer letters than the rack
  // size, so the player opens to a full rack. No-op if nothing is empty.
  void fillEmptyBaseRackSlots() {
    final base = state.config.rackSize;
    final rack = List<String?>.from(state.rackCells);
    final pool = List<String>.from(state.pool);
    final drawnLetters = <String>[];
    for (int i = 0; i < base && i < rack.length && pool.isNotEmpty; i++) {
      if (rack[i] != null) continue;
      final drawn = _drawRefill(pool, rack);
      rack[i] = drawn;
      drawnLetters.add(drawn);
    }
    if (drawnLetters.isEmpty) return;
    state = state.copyWith(
      rackCells: rack,
      pool: pool,
      dealtLetters: [...state.dealtLetters, ...drawnLetters],
    );
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

  // Draws one extra letter from the pool -- a pure bonus, no cost. Goes
  // into the first empty rack slot if there is one; otherwise (always the
  // case in Infinite Estate, whose rack refills itself and so is never
  // short) a new bonus slot is added to the end of the rack, so the reward
  // actually arrives instead of silently doing nothing. Returns whether a
  // letter was drawn: false only if the pool is empty, so callers can
  // avoid using up a one-time reward that gave the player nothing.
  // Generic, not landmark-specific: any mode/event that wants to hand the
  // player a free letter can use this.
  bool drawBonusLetter() {
    if (state.pool.isEmpty) return false;

    final pool = List<String>.from(state.pool)..shuffle();
    final drawn = pool.removeLast();
    final rack = List<String?>.from(state.rackCells);
    final emptyIndex = rack.indexWhere((c) => c == null);
    if (emptyIndex == -1) {
      rack.add(drawn);
    } else {
      rack[emptyIndex] = drawn;
    }

    state = state.copyWith(
      rackCells: rack,
      pool: pool,
      dealtLetters: [...state.dealtLetters, drawn],
    );
    return true;
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
    // A saved rack may be longer than rackSize if it held unplaced bonus
    // letters (see drawBonusLetter), but never shorter.
    if (rackCells.length < state.config.rackSize) return;
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
