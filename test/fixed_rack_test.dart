import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_game_controller.dart';
import 'package:namer_app/game/tile_location.dart';

void main() {
  GridGameController build() => GridGameController(
        const GridConfig(boardWidth: 10, boardHeight: 10, rackSize: 3, initialRack: ['C', 'A', 'T']),
      );

  test('initialRack deals exactly those letters, in order, with an empty pool', () {
    final controller = build();
    expect(controller.state.rackCells, ['C', 'A', 'T']);
    expect(controller.state.pool, isEmpty);
    expect(controller.state.dealtLetters, ['C', 'A', 'T']);
    expect(controller.state.isPoolEmptied, isFalse);
  });

  test('all letters placed is reported once the rack is empty', () {
    final controller = build();
    for (int i = 0; i < 3; i++) {
      expect(controller.state.isPoolEmptied, isFalse);
      controller.moveTile(TileLocation(TileZone.rack, i), TileLocation(TileZone.board, i));
    }
    expect(controller.state.rackCells.every((c) => c == null), isTrue);
    expect(controller.state.isPoolEmptied, isTrue);
  });

  test('with no pool, a bonus draw gives nothing', () {
    expect(build().drawBonusLetter(), isFalse);
  });
}
