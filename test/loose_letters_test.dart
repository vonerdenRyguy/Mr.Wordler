import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/tile_location.dart';
import 'package:namer_app/game/word_runs.dart';

Future<bool> _isWord(String w) async => const {'CAT', 'AX'}.contains(w);

void main() {
  const config = GridConfig(boardWidth: 3, boardHeight: 2, rackSize: 2, refillRackOnPlace: true);

  (ProviderContainer, dynamic) build(List<String?> board, List<String?> rack, [List<String> pool = const []]) {
    final c = ProviderContainer(overrides: [gridConfigProvider.overrideWithValue(config)]);
    addTearDown(c.dispose);
    final ctl = c.read(gridGameControllerProvider.notifier);
    ctl.restoreState(boardCells: board, rackCells: rack, pool: pool, dealtLetters: const []);
    return (c, ctl);
  }

  test('currentWordRuns only returns settled words', () async {
    final (_, ctl) = build(['C', 'A', 'T', null, 'Q', null], [null, null]);
    expect(await ctl.currentWordRuns(isValid: _isWord), isEmpty);
    expect(await ctl.looseCells(isValid: _isWord), {1, 4});
  });

  test('after the fix the word counts', () async {
    final (_, ctl) = build(['C', 'A', 'T', null, 'X', null], [null, null]);
    expect((await ctl.currentWordRuns(isValid: _isWord)).map((r) => r.word).toSet(), {'CAT', 'AX'});
    expect(await ctl.looseCells(isValid: _isWord), isEmpty);
  });

  test('returnLooseToRack takes only stray letters: free slots first, then the bag', () async {
    // ZQY is no word; CAT is a real word even though AQ taints it.
    final (c, ctl) = build(['C', 'A', 'T', 'Z', 'Q', 'Y'], ['E', null]);
    final n = await ctl.returnLooseToRack(isValid: _isWord);
    final s = c.read(gridGameControllerProvider);
    // Z, Q and Y are in no real word. The A of CAT is shared: CAT stays.
    expect(n, 3);
    expect(s.boardCells, ['C', 'A', 'T', null, null, null]);
    expect(s.rackCells, hasLength(2));
    expect(s.rackCells.whereType<String>().length, 2);
    expect(s.bag, ['Q', 'Y']); // the free slot took the first (Z)
  });

  test('CAT with a Q under the A returns only the Q', () async {
    final (c, ctl) = build(['C', 'A', 'T', null, 'Q', null], ['E', 'F']);
    expect(await ctl.returnLooseToRack(isValid: _isWord), 1);
    final s = c.read(gridGameControllerProvider);
    expect(s.boardCells, ['C', 'A', 'T', null, null, null]);
    expect(s.bag, ['Q']);
  });

  test('a lone letter returns', () async {
    final (c, ctl) = build([null, null, null, null, 'Z', null], ['E', 'F']);
    expect(await ctl.returnLooseToRack(isValid: _isWord), 1);
    expect(c.read(gridGameControllerProvider).bag, ['Z']);
  });

  test('a letter shared by two real words never moves', () async {
    // CAT across and AX down share the A.
    final (c, ctl) = build(['C', 'A', 'T', null, 'X', null], ['E', 'F']);
    expect(await ctl.returnLooseToRack(isValid: _isWord), 0);
    expect(c.read(gridGameControllerProvider).boardCells, ['C', 'A', 'T', null, 'X', null]);
  });

  test('cells in keep (a found special, a villager) are never taken', () async {
    final (c, ctl) = build([null, null, null, null, 'Z', null], ['E', 'F']);
    expect(await ctl.returnLooseToRack(isValid: _isWord, keep: {4}), 0);
    expect(c.read(gridGameControllerProvider).boardCells[4], 'Z');
  });

  test('kept words keep standing in a bad crossing, and drop out once a letter moves', () async {
    // BARN-like: CAT across, with Q under the A ("AQ" is no word).
    final board = <String?>['C', 'A', 'T', null, 'Q', null];
    final (c, ctl) = build(board, ['E', 'F']);
    final kept = [WordRun('CAT', [0, 1, 2], true)];
    expect((await ctl.currentWordRuns(isValid: _isWord)), isEmpty);
    expect((await ctl.currentWordRuns(isValid: _isWord, kept: kept)).map((r) => r.word), ['CAT']);
    // The Q goes back: A is still on the board, building stays.
    expect(await ctl.returnLooseToRack(isValid: _isWord), 1);
    final after = c.read(gridGameControllerProvider);
    expect(after.boardCells[1], 'A');
    expect((await ctl.currentWordRuns(isValid: _isWord, kept: kept)).map((r) => r.word), ['CAT']);
    // Picking up a letter ends the keeping.
    expect(pruneKept(kept, ['C', 'A', 'T', null, null, null]), kept);
    expect(pruneKept(kept, ['C', null, 'T', null, null, null]), isEmpty);
    expect(pruneKept(kept, ['C', 'B', 'T', null, null, null]), isEmpty);
  });

  test('33 returned letters make a normal rack plus a bag of the rest, and the bag feeds the rack', () async {
    final big = GridConfig(boardWidth: 40, boardHeight: 1, rackSize: 10, refillRackOnPlace: true);
    final c = ProviderContainer(overrides: [gridConfigProvider.overrideWithValue(big)]);
    addTearDown(c.dispose);
    final ctl = c.read(gridGameControllerProvider.notifier);
    // 33 lone letters (spaced so none touches), rack empty.
    final board = List<String?>.filled(40, null);
    for (var i = 0; i < 20; i++) {
      board[i * 2] = 'Z';
    }
    ctl.restoreState(
      boardCells: board,
      rackCells: List<String?>.filled(10, null),
      pool: ['A', 'B'],
      dealtLetters: const [],
    );
    expect(await ctl.returnLooseToRack(isValid: _isWord), 20);
    var s = c.read(gridGameControllerProvider);
    expect(s.rackCells, hasLength(10));
    expect(s.rackCells.whereType<String>(), hasLength(10));
    expect(s.bag, hasLength(10));
    ctl.moveTile(const TileLocation(TileZone.rack, 0), const TileLocation(TileZone.board, 1));
    s = c.read(gridGameControllerProvider);
    expect(s.bag, hasLength(9));
    expect(s.pool, ['A', 'B'], reason: 'nothing is dealt while the bag has letters');
    expect(s.rackCells.whereType<String>(), hasLength(10));
  });

  test('returnLooseToRack keeps settled tiles and does nothing when none are loose', () async {
    final (c, ctl) = build(['C', 'A', 'T', null, 'X', null], ['E', 'F']);
    expect(await ctl.returnLooseToRack(isValid: _isWord), 0);
    expect(c.read(gridGameControllerProvider).boardCells[0], 'C');
  });

  test('with letters in the bag a refill comes from the bag first', () {
    final (c, ctl) = build([null, null, null, null, null, null], ['A', 'B'], ['X', 'Y']);
    ctl.restoreState(
      boardCells: List<String?>.filled(6, null),
      rackCells: ['A', 'B'],
      pool: ['X', 'Y'],
      dealtLetters: <String>[],
      bag: ['G'],
    );
    ctl.moveTile(const TileLocation(TileZone.rack, 0), const TileLocation(TileZone.board, 0));
    final s = c.read(gridGameControllerProvider);
    expect(s.rackCells[0], 'G');
    expect(s.pool.length, 2);
  });
}
