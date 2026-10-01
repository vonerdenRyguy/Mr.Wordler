import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/tile_location.dart';

// Farm structure ability: preferBalancedRefill steers the auto-refill-on-
// place draw toward whichever of vowel/consonant the rack has fewer of,
// but must never leave a player worse off than a plain random draw would
// have.
void main() {
  const config = GridConfig(
    boardWidth: 3,
    boardHeight: 1,
    rackSize: 3,
    refillRackOnPlace: true,
  );

  ProviderContainer buildContainer() {
    final container = ProviderContainer(overrides: [gridConfigProvider.overrideWithValue(config)]);
    addTearDown(container.dispose);
    return container;
  }

  test('balanced refill draws the pool\'s only vowel when the rack is consonant-heavy', () {
    final container = buildContainer();
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D'],
      pool: ['X', 'A', 'Y'],
      dealtLetters: ['B', 'C', 'D'],
    );

    controller.moveTile(
      const TileLocation(TileZone.rack, 0),
      const TileLocation(TileZone.board, 0),
      preferBalancedRefill: true,
    );

    final state = container.read(gridGameControllerProvider);
    expect(state.boardCells[0], 'B');
    expect(state.rackCells[0], 'A');
  });

  test('balanced refill draws the pool\'s only consonant when the rack is vowel-heavy', () {
    final container = buildContainer();
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['A', 'E', 'D'],
      pool: ['I', 'O', 'Z'],
      dealtLetters: ['A', 'E', 'D'],
    );

    controller.moveTile(
      const TileLocation(TileZone.rack, 0),
      const TileLocation(TileZone.board, 0),
      preferBalancedRefill: true,
    );

    final state = container.read(gridGameControllerProvider);
    expect(state.rackCells[0], 'Z');
  });

  test('falls back to a normal draw (never leaving the slot empty) when the pool has none of the preferred type', () {
    final container = buildContainer();
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D'],
      pool: ['X', 'Y', 'Z'],
      dealtLetters: ['B', 'C', 'D'],
    );

    controller.moveTile(
      const TileLocation(TileZone.rack, 0),
      const TileLocation(TileZone.board, 0),
      preferBalancedRefill: true,
    );

    final state = container.read(gridGameControllerProvider);
    expect(state.rackCells[0], isNotNull);
    expect(['X', 'Y', 'Z'], contains(state.rackCells[0]));
  });

  test('preferBalancedRefill defaults to off (plain random draw) when not requested', () {
    final container = buildContainer();
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: [null, null, null],
      rackCells: ['B', 'C', 'D'],
      pool: ['A'],
      dealtLetters: ['B', 'C', 'D'],
    );

    controller.moveTile(const TileLocation(TileZone.rack, 0), const TileLocation(TileZone.board, 0));

    final state = container.read(gridGameControllerProvider);
    expect(state.boardCells[0], 'B');
    expect(state.rackCells[0], 'A');
    expect(state.pool, isEmpty);
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
