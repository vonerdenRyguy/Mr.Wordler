import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/valid_word_check.dart';
import 'grid_game_state.dart';
import 'grid_providers.dart';
import 'letter_tile.dart';
import 'word_runs.dart';

// Word-landing feedback: every time exactly one tile lands on the board,
// that tile "settles", and any real words it completes pop, glow and show
// in a banner. Pure reward -- an invalid word gets no feedback at all.
// Lives in the shared engine (no per-screen code), and never touches
// GridGameController/GridGameState: it only watches them.

typedef WordCheck = Future<bool> Function(String word);

/// Overridable in tests. The real one uses the shared dictionary.
final wordCheckProvider = Provider<WordCheck>((ref) => WordValidator().isValidWord);

class TileLanding {
  final int seq; // increases on every landing
  final int placedIndex;
  final List<WordRun> words; // empty until the dictionary check finishes
  const TileLanding(this.seq, this.placedIndex, this.words);
}

class TileLandingNotifier extends StateNotifier<TileLanding?> {
  TileLandingNotifier(this._wordCheck) : super(null);

  final WordCheck _wordCheck;
  int _seq = 0;
  // Bumped on every board change (removals included), so a word check
  // that finishes after the board has moved on is thrown away.
  int _boardVersion = 0;

  void onStateChanged(GridGameState? prev, GridGameState next) {
    if (prev == null) return;
    if (identical(prev.boardCells, next.boardCells)) return;
    if (prev.boardCells.length != next.boardCells.length) return;
    _boardVersion++;

    // Exactly one empty cell must have gained a letter. Zero is a pick-up
    // or rack-only change; more than one is a restore.
    int? placed;
    for (int i = 0; i < next.boardCells.length; i++) {
      if (prev.boardCells[i] == null && next.boardCells[i] != null) {
        if (placed != null) return;
        placed = i;
      }
    }
    if (placed == null) return;

    final seq = ++_seq;
    state = TileLanding(seq, placed, const []);
    _checkWords(seq, _boardVersion, next, placed);
  }

  Future<void> _checkWords(int seq, int boardVersion, GridGameState board, int placed) async {
    final runs = runsThrough(board.boardCells, board.config.boardWidth, board.config.boardHeight, placed);
    final valid = <WordRun>[];
    for (final run in runs) {
      if (await _wordCheck(run.word)) valid.add(run);
    }
    if (!mounted || seq != _seq || boardVersion != _boardVersion || valid.isEmpty) return;
    state = TileLanding(seq, placed, valid);
  }
}

final tileLandingProvider = StateNotifierProvider.autoDispose<TileLandingNotifier, TileLanding?>((ref) {
  final notifier = TileLandingNotifier(ref.read(wordCheckProvider));
  ref.listen<GridGameState>(gridGameControllerProvider, (prev, next) => notifier.onStateChanged(prev, next));
  return notifier;
}, dependencies: [gridGameControllerProvider, wordCheckProvider]);

/// What the board tile at [index] should animate for [landing], or null if
/// it isn't involved. popOrder is the tile's position across all new words
/// in reading order (a tile shared by two words counts once).
TileFx? fxFor(TileLanding? landing, int index) {
  if (landing == null) return null;
  final settle = landing.placedIndex == index;
  var popOrder = -1;
  var order = 0;
  final seen = <int>{};
  for (final word in landing.words) {
    for (final position in word.positions) {
      if (!seen.add(position)) continue;
      if (position == index) popOrder = order;
      order++;
    }
  }
  if (!settle && popOrder == -1) return null;
  return (seq: landing.seq, settle: settle, popOrder: popOrder);
}
