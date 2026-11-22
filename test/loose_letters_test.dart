import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/tile_location.dart';

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

  test('returnLooseToRack fills free slots, then goes past the rack size', () async {
    final (c, ctl) = build(['C', 'A', 'T', 'Z', 'Q', 'Y'], ['E', null]);
    final n = await ctl.returnLooseToRack(isValid: _isWord);
    final s = c.read(gridGameControllerProvider);
    // ZQY is no word, and AQ taints CAT: all six are loose.
    expect(n, 6);
    expect(s.boardCells.whereType<String>(), isEmpty);
    expect(s.rackCells.length, greaterThan(2));
    expect(s.rackCells.whereType<String>().length, 7);
  });

  test('returnLooseToRack keeps settled tiles and does nothing when none are loose', () async {
    final (c, ctl) = build(['C', 'A', 'T', null, 'X', null], ['E', 'F']);
    expect(await ctl.returnLooseToRack(isValid: _isWord), 0);
    expect(c.read(gridGameControllerProvider).boardCells[0], 'C');
  });

  test('refills wait until the rack is back under its size', () {
    final (c, ctl) = build([null, null, null, null, null, null], ['A', 'B', 'G'], ['X', 'Y']);
    ctl.moveTile(const TileLocation(TileZone.rack, 0), const TileLocation(TileZone.board, 0));
    final s = c.read(gridGameControllerProvider);
    expect(s.rackCells[0], isNull);
    expect(s.pool.length, 2);
  });
}
