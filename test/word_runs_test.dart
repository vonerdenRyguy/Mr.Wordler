import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/word_runs.dart';

void main() {
  // Builds a width x height board from rows of text; '.' is empty.
  List<String?> board(List<String> rows) => [
        for (final row in rows)
          for (final ch in row.split('')) ch == '.' ? null : ch,
      ];

  test('an across run through the middle of a word returns the whole word, in order', () {
    final b = board(['.CAT.', '.....']);
    expect(runsThrough(b, 5, 2, 2), [const WordRun('CAT', [1, 2, 3], true)]);
  });

  test('a down run works the same way', () {
    final b = board(['.C.', '.A.', '.T.']);
    expect(runsThrough(b, 3, 3, 4), [const WordRun('CAT', [1, 4, 7], false)]);
  });

  test('a tile in both an across and a down word returns both', () {
    final b = board(['CAT', '.X.', '.E.']);
    expect(runsThrough(b, 3, 3, 1), [
      const WordRun('CAT', [0, 1, 2], true),
      const WordRun('AXE', [1, 4, 7], false),
    ]);
  });

  test('a single letter with no neighbors returns nothing', () {
    final b = board(['...', '.A.', '...']);
    expect(runsThrough(b, 3, 3, 4), isEmpty);
  });

  test('a run at the right edge does not wrap onto the next row', () {
    final b = board(['.AB', 'C..']);
    expect(runsThrough(b, 3, 2, 2), [const WordRun('AB', [1, 2], true)]);
  });
}
