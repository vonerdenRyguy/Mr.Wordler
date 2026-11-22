import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/word_runs.dart';

const _words = {'CAT', 'CATS', 'AT', 'BRIDGE', 'ROBIN', 'FERN', 'FOX', 'NEST', 'TREE', 'TO', 'AX'};
Future<bool> _isWord(String w) async => _words.contains(w);

List<String?> board(List<String> rows) =>
    [for (final r in rows) for (final c in r.split('')) c == '.' ? null : c];

Future<BoardWords> run(List<String> rows) =>
    settle(board(rows), rows.first.length, rows.length, _isWord);

void main() {
  test('CAT with a bad crossing settles nothing; A and Q are loose', () async {
    final r = await run(['CAT', '.Q.']);
    expect(r.settledRuns, isEmpty);
    expect(r.badRuns.map((b) => b.word), ['AQ']);
    expect(r.looseCells, {1, 4});
  });

  test('fixing the crossing settles both words', () async {
    final r = await run(['CAT', '.X.']);
    expect(r.settledRuns.map((b) => b.word).toSet(), {'CAT', 'AX'});
    expect(r.looseCells, isEmpty);
  });

  test('a lone letter is loose, even beside a settled word', () async {
    final r = await run(['CAT...', '.....Z']);
    expect(r.settledRuns.map((b) => b.word), ['CAT']);
    expect(r.looseCells, {11});
  });

  test('two-letter words settle', () async {
    final r = await run(['TO']);
    expect(r.settledRuns.single.word, 'TO');
    expect(r.looseCells, isEmpty);
  });

  test('a misspelled run alone is all loose', () async {
    final r = await run(['CAX']);
    expect(r.settledRuns, isEmpty);
    expect(r.looseCells, {0, 1, 2});
  });

  test('the X254 board settles all six words', () async {
    final r = await run([
      '...BRIDGE',
      '....O....',
      '....B....',
      '....I....',
      '.FERN....',
      '.O.......',
      '.X.T.....',
      '...R.....',
      '..NEST...',
      '...E.....',
    ].map((s) => s.padRight(9, '.')).toList());
    expect(r.settledRuns.map((b) => b.word).toSet(),
        {'BRIDGE', 'ROBIN', 'FERN', 'FOX', 'NEST', 'TREE'});
    expect(r.looseCells, isEmpty);
  });
}
