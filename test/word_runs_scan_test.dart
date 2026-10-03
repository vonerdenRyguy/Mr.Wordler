import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/components/valid_word_check.dart';
import 'package:namer_app/game/word_runs.dart';
import 'package:namer_app/village/structures.dart';

void main() {
  const words = {'WELL', 'THE', 'HE', 'TE'};
  Future<bool> fakeCheck(String w) async => words.contains(w);

  // Builds a board from rows of text; '.' is empty.
  List<String?> board(List<String> rows) => [
        for (final row in rows)
          for (final ch in row.split('')) ch == '.' ? null : ch,
      ];

  test('two WELLs in two places are two runs and two structures', () async {
    final b = board([
      'WELL......',
      '..........',
      '......WELL',
    ]);
    final runs = await WordValidator().findValidRuns(b, 10, 3, isValid: fakeCheck);
    expect(runs.where((r) => r.word == 'WELL').length, 2);
    final structures = computeStructures(runs);
    expect(structures.length, 2);
    expect(structures[0].positions, {0, 1, 2, 3});
    expect(structures[1].positions, {26, 27, 28, 29});
  });

  test('THE across and THE down elsewhere both appear', () async {
    final b = board([
      'THE....T',
      '.......H',
      '.......E',
    ]);
    final runs = await WordValidator().findValidRuns(b, 8, 3, isValid: fakeCheck);
    expect(runs, containsAll([
      const WordRun('THE', [0, 1, 2], true),
      const WordRun('THE', [7, 15, 23], false),
    ]));
  });

  test('single letters are never runs', () async {
    final b = board(['A.B', '...', 'C.D']);
    final runs = await WordValidator().findValidRuns(b, 3, 3, isValid: (_) async => true);
    expect(runs, isEmpty);
  });

  test('a down structure keeps its direction and middle cell', () async {
    final b = board(['W.', 'E.', 'L.', 'L.']);
    final runs = await WordValidator().findValidRuns(b, 2, 4, isValid: fakeCheck);
    final s = computeStructures(runs).single;
    expect(s.across, isFalse);
    expect(s.ordered, [0, 2, 4, 6]);
    expect(s.middle, 2);
  });
}
