// A straight line of 2+ letters on the board, across or down.
class WordRun {
  final String word;
  final List<int> positions; // board indices, in reading order
  final bool across;
  const WordRun(this.word, this.positions, this.across);

  @override
  bool operator ==(Object other) =>
      other is WordRun && other.word == word && other.across == across && _sameList(other.positions, positions);

  @override
  int get hashCode => Object.hash(word, across, Object.hashAll(positions));

  @override
  String toString() => 'WordRun($word, ${across ? 'across' : 'down'}, $positions)';

  static bool _sameList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The across run and the down run that pass through [index], each kept
/// only if it is 2+ letters long. A run stops at an empty cell or the
/// board edge, and never wraps to the next row.
List<WordRun> runsThrough(List<String?> board, int width, int height, int index) {
  if (index < 0 || index >= board.length || board[index] == null) return const [];
  final row = index ~/ width;
  final col = index % width;
  final runs = <WordRun>[];

  // Across: walk left to the start of the run, then right to its end.
  var startCol = col;
  while (startCol > 0 && board[row * width + startCol - 1] != null) {
    startCol--;
  }
  final across = <int>[];
  for (int c = startCol; c < width && board[row * width + c] != null; c++) {
    across.add(row * width + c);
  }
  if (across.length >= 2) {
    runs.add(WordRun(across.map((i) => board[i]!).join(), across, true));
  }

  // Down: same, by rows.
  var startRow = row;
  while (startRow > 0 && board[(startRow - 1) * width + col] != null) {
    startRow--;
  }
  final down = <int>[];
  for (int r = startRow; r < height && board[r * width + col] != null; r++) {
    down.add(r * width + col);
  }
  if (down.length >= 2) {
    runs.add(WordRun(down.map((i) => board[i]!).join(), down, false));
  }

  return runs;
}

/// The result of [settle]: which runs count, which don't, and which
/// letters are loose.
class BoardWords {
  /// Valid runs whose every letter is settled. Only these count.
  final List<WordRun> settledRuns;

  /// Runs of 2+ letters that are not words.
  final List<WordRun> badRuns;

  /// Board indices of letters that are not settled: in a misspelled run,
  /// in a valid run that crosses one, or standing alone.
  final Set<int> looseCells;

  const BoardWords(this.settledRuns, this.badRuns, this.looseCells);
}

/// Splits the board into settled and loose letters. A letter is settled
/// when every run through it (across and down, 2+ letters) is a real word
/// and it belongs to at least one such run. Everything else is loose.
Future<BoardWords> settle(
  List<String?> cells,
  int w,
  int h,
  Future<bool> Function(String word) isValid,
) async {
  assert(cells.length == w * h);
  final valid = <WordRun>[];
  final bad = <WordRun>[];

  Future<void> scanLine(int count, int Function(int i) indexAt, bool across) async {
    var positions = <int>[];
    Future<void> flush() async {
      if (positions.length > 1) {
        final word = positions.map((i) => cells[i]!).join();
        (await isValid(word) ? valid : bad).add(WordRun(word, positions, across));
      }
      positions = <int>[];
    }

    for (int i = 0; i < count; i++) {
      final index = indexAt(i);
      if (cells[index] != null) {
        positions.add(index);
      } else {
        await flush();
      }
    }
    await flush();
  }

  for (int row = 0; row < h; row++) {
    await scanLine(w, (col) => row * w + col, true);
  }
  for (int col = 0; col < w; col++) {
    await scanLine(h, (row) => row * w + col, false);
  }

  final tainted = <int>{for (final r in bad) ...r.positions};
  final inValid = <int>{for (final r in valid) ...r.positions};
  final loose = <int>{
    for (int i = 0; i < cells.length; i++)
      if (cells[i] != null && (tainted.contains(i) || !inValid.contains(i))) i,
  };
  final settled = [
    for (final r in valid)
      if (!r.positions.any(loose.contains)) r,
  ];
  return BoardWords(settled, bad, loose);
}
