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

/// The gold star's square while a brand-new village's first word must cover
/// it (spec-18b); null everywhere else. The village has its own copy.
final startCellProvider = StateProvider<int?>((ref) => null, dependencies: const []);

class TileLanding {
  final int seq; // increases on every landing
  final int placedIndex;
  final List<WordRun> words; // empty until the dictionary check finishes
  const TileLanding(this.seq, this.placedIndex, this.words);
}

class TileLandingNotifier extends StateNotifier<TileLanding?> {
  TileLandingNotifier(this._wordCheck, [this._startCell]) : super(null);

  final int? Function()? _startCell;

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

    // At most one empty cell may have gained a letter. More than one is a
    // restore. Letters that left a cell matter too: taking away a bad
    // crossing can settle the word beside it.
    int? placed;
    final removed = <int>[];
    for (int i = 0; i < next.boardCells.length; i++) {
      final before = prev.boardCells[i];
      final after = next.boardCells[i];
      if (before == null && after != null) {
        if (placed != null) return;
        placed = i;
      } else if (before != null && after == null) {
        removed.add(i);
      }
    }
    if (placed == null && removed.isEmpty) return;

    final seq = ++_seq;
    if (placed != null) state = TileLanding(seq, placed, const []);
    _checkWords(seq, _boardVersion, prev, next, placed, removed);
  }

  Future<void> _checkWords(
    int seq,
    int boardVersion,
    GridGameState before,
    GridGameState board,
    int? placed,
    List<int> removed,
  ) async {
    final w = board.config.boardWidth;
    final h = board.config.boardHeight;
    final candidates = <int>[
      if (placed != null) placed,
      for (final r in removed) ..._neighbours(r, w, h).where((n) => board.boardCells[n] != null),
    ];
    // Only words that are settled now and weren't before count as landing:
    // a word with a misspelled crossing stays quiet until it is fixed.
    final now = await _settledThrough(board.boardCells, w, h, candidates);
    final was = placed == null && removed.isEmpty
        ? const <WordRun>[]
        : await _settledThrough(before.boardCells, w, h, candidates);
    final fresh = [
      for (final run in now)
        if (!was.contains(run)) run,
    ];
    if (!mounted || seq != _seq || boardVersion != _boardVersion || fresh.isEmpty) return;
    final start = _startCell?.call();
    if (start != null && !fresh.any((r) => r.positions.contains(start))) return;
    state = TileLanding(seq, placed ?? fresh.first.positions.first, fresh);
  }

  Iterable<int> _neighbours(int i, int w, int h) sync* {
    final r = i ~/ w, c = i % w;
    if (r > 0) yield i - w;
    if (r < h - 1) yield i + w;
    if (c > 0) yield i - 1;
    if (c < w - 1) yield i + 1;
  }

  // Valid runs through [indices] whose every letter is settled (every run
  // through every letter is a real word).
  Future<List<WordRun>> _settledThrough(List<String?> cells, int w, int h, Iterable<int> indices) async {
    final cache = <String, bool>{};
    Future<bool> ok(String word) async => cache[word] ??= await _wordCheck(word);
    final out = <WordRun>[];
    for (final idx in indices) {
      for (final run in runsThrough(cells, w, h, idx)) {
        if (out.contains(run) || !await ok(run.word)) continue;
        var settled = true;
        for (final p in run.positions) {
          for (final cross in runsThrough(cells, w, h, p)) {
            if (!await ok(cross.word)) {
              settled = false;
              break;
            }
          }
          if (!settled) break;
        }
        if (settled) out.add(run);
      }
    }
    return out;
  }
}

final tileLandingProvider = StateNotifierProvider.autoDispose<TileLandingNotifier, TileLanding?>((ref) {
  final notifier = TileLandingNotifier(ref.read(wordCheckProvider), () => ref.read(startCellProvider));
  ref.listen<GridGameState>(gridGameControllerProvider, (prev, next) => notifier.onStateChanged(prev, next));
  return notifier;
}, dependencies: [gridGameControllerProvider, wordCheckProvider, startCellProvider]);

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
