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
}
