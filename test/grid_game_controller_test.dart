import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_game_state.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/tile_location.dart';

// Infinite Estate's rack rules (balancedRefill, swapRack), plus checks
// that the 10x10 modes' plain rack is untouched.
void main() {
  const config = GridConfig(
    boardWidth: 3,
    boardHeight: 1,
    rackSize: 3,
    refillRackOnPlace: true,
  );
  const balancedConfig = GridConfig(
    boardWidth: 3,
    boardHeight: 1,
    rackSize: 3,
    refillRackOnPlace: true,
    balancedRefill: true,
  );

  ProviderContainer buildContainer([GridConfig c = config]) {
    final container = ProviderContainer(overrides: [gridConfigProvider.overrideWithValue(c)]);
    addTearDown(container.dispose);
    return container;
  }

  List<String> allLetters(GridGameState s) => [
        ...s.boardCells.whereType<String>(),
        ...s.rackCells.whereType<String>(),
        ...s.pool,
      ]..sort();

  test('balanced refill: a consonant-heavy rack refills with a vowel', () {
    final container = buildContainer(balancedConfig);
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D'],
      pool: ['X', 'A', 'Y'],
      dealtLetters: ['B', 'C', 'D'],
    );

    controller.moveTile(const TileLocation(TileZone.rack, 0), const TileLocation(TileZone.board, 0));

    final state = container.read(gridGameControllerProvider);
    expect(state.boardCells[0], 'B');
    expect(state.rackCells[0], 'A');
  });

  test('balanced refill: placing a tile never pushes the rack past 2 hard letters', () {
    final container = buildContainer(balancedConfig);
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'Z', 'X'],
      pool: ['J', 'K', 'Q', 'V', 'T'],
      dealtLetters: ['B', 'Z', 'X'],
    );

    controller.moveTile(const TileLocation(TileZone.rack, 0), const TileLocation(TileZone.board, 0));

    expect(container.read(gridGameControllerProvider).rackCells[0], 'T');
  });

  test('swapRack: unpinned base slots get new letters, pinned ones and bonus slots are kept', () {
    final container = buildContainer(balancedConfig);
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: ['C', null, null],
      rackCells: ['B', 'D', 'F', 'G'], // index 3 is a bonus slot
      pool: ['A', 'E', 'I', 'O'],
      dealtLetters: ['C', 'B', 'D', 'F', 'G'],
    );
    final before = container.read(gridGameControllerProvider);

    expect(controller.swapRack(keepIndices: {1}), isTrue);

    final state = container.read(gridGameControllerProvider);
    expect(state.rackCells[1], 'D');
    expect(state.rackCells[3], 'G');
    expect(state.rackCells.length, 4);
    // The new letters come from the old pool, not the letters just returned.
    expect(['A', 'E', 'I', 'O'], contains(state.rackCells[0]));
    expect(['A', 'E', 'I', 'O'], contains(state.rackCells[2]));
    expect(state.pool, containsAll(['B', 'F']));
    // Nothing created or lost.
    expect(allLetters(state), allLetters(before));
    final dealt = List<String>.from(state.dealtLetters)..sort();
    final onBoardOrRack = [...state.boardCells.whereType<String>(), ...state.rackCells.whereType<String>()]..sort();
    expect(dealt, onBoardOrRack);
  });

  test('swapRack returns false and changes nothing on an empty pool', () {
    final container = buildContainer(balancedConfig);
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'D', 'F'],
      pool: [],
      dealtLetters: ['B', 'D', 'F'],
    );

    expect(controller.swapRack(keepIndices: {}), isFalse);
    expect(container.read(gridGameControllerProvider).rackCells, ['B', 'D', 'F']);
  });

  test('swapRack returns false when every base letter is pinned', () {
    final container = buildContainer(balancedConfig);
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'D', 'F'],
      pool: ['A'],
      dealtLetters: ['B', 'D', 'F'],
    );

    expect(controller.swapRack(keepIndices: {0, 1, 2}), isFalse);
    expect(container.read(gridGameControllerProvider).pool, ['A']);
  });

  test('10x10-style config (no refill flag): placing a tile does not refill', () {
    final container = buildContainer(const GridConfig(boardWidth: 3, boardHeight: 1, rackSize: 3));
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D'],
      pool: ['A'],
      dealtLetters: ['B', 'C', 'D'],
    );

    controller.moveTile(const TileLocation(TileZone.rack, 0), const TileLocation(TileZone.board, 0));

    final state = container.read(gridGameControllerProvider);
    expect(state.rackCells, [null, 'C', 'D']);
    expect(state.pool, ['A']);
  });

  test('10x10-style config: tradeIn still swaps 1 letter for 3', () {
    final container = buildContainer(const GridConfig(boardWidth: 3, boardHeight: 1, rackSize: 5));
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['Q', null, null, null, 'B'],
      pool: ['A', 'E', 'I'],
      dealtLetters: ['Q', 'B'],
    );

    expect(controller.tradeIn(0), isTrue);

    final state = container.read(gridGameControllerProvider);
    expect(state.rackCells.whereType<String>().length, 4);
    expect(state.pool.length, 1);
    expect([...state.rackCells.whereType<String>(), ...state.pool]..sort(), ['A', 'B', 'E', 'I', 'Q']);
  });

  // drawBonusLetter used to require an empty rack slot, which a
  // refill-on-place rack (Infinite Estate) never has -- so landmark and
  // Well rewards silently gave nothing. It now adds a bonus slot instead.
  test('bonus letter adds a slot when the rack is full', () {
    final container = buildContainer();
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D'],
      pool: ['E'],
      dealtLetters: ['B', 'C', 'D'],
    );

    final gotLetter = controller.drawBonusLetter();

    final state = container.read(gridGameControllerProvider);
    expect(gotLetter, isTrue);
    expect(state.rackCells, ['B', 'C', 'D', 'E']);
    expect(state.pool, isEmpty);
  });

  test('bonus letter reports false and changes nothing when the pool is empty', () {
    final container = buildContainer();
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D'],
      pool: [],
      dealtLetters: ['B', 'C', 'D'],
    );

    expect(controller.drawBonusLetter(), isFalse);
    expect(container.read(gridGameControllerProvider).rackCells, ['B', 'C', 'D']);
  });

  test('placing a bonus letter does not refill, and its slot goes away', () {
    final container = buildContainer();
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D', 'E'],
      pool: ['X', 'Y'],
      dealtLetters: ['B', 'C', 'D', 'E'],
    );

    controller.moveTile(
      const TileLocation(TileZone.rack, 3),
      const TileLocation(TileZone.board, 0),
    );

    final state = container.read(gridGameControllerProvider);
    expect(state.boardCells[0], 'E');
    expect(state.rackCells, ['B', 'C', 'D']);
    expect(state.pool.length, 2);
  });

  test('placing a base rack letter still refills its slot', () {
    final container = buildContainer();
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D', 'E'],
      pool: ['X'],
      dealtLetters: ['B', 'C', 'D', 'E'],
    );

    controller.moveTile(
      const TileLocation(TileZone.rack, 0),
      const TileLocation(TileZone.board, 0),
    );

    final state = container.read(gridGameControllerProvider);
    expect(state.rackCells, ['X', 'C', 'D', 'E']);
  });

  test('a saved rack holding unplaced bonus letters restores', () {
    final container = buildContainer();
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D', 'E', 'F'],
      pool: [],
      dealtLetters: ['B', 'C', 'D', 'E', 'F'],
    );

    expect(container.read(gridGameControllerProvider).rackCells.length, 5);
  });
}
