import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/village/village_save.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load returns null when nothing has been saved yet', () async {
    final controller = VillageSaveController();
    expect(await controller.load(), isNull);
  });

  test('save then load round-trips board/rack/pool/dealtLetters/lastCashedOutScore', () async {
    final controller = VillageSaveController();
    final data = VillageSaveData(
      boardCells: ['W', 'E', 'L', 'L', null, null],
      rackCells: List<String?>.generate(21, (i) => i < 3 ? 'A' : null),
      pool: ['B', 'C', 'D'],
      dealtLetters: ['W', 'E', 'L', 'L', 'A', 'A', 'A'],
      lastCashedOutScore: 42,
    );

    await controller.save(data);
    final loaded = await controller.load();

    expect(loaded, isNotNull);
    expect(loaded!.boardCells, data.boardCells);
    expect(loaded.rackCells, data.rackCells);
    expect(loaded.pool, data.pool);
    expect(loaded.dealtLetters, data.dealtLetters);
    expect(loaded.lastCashedOutScore, 42);
  });

  test('a second save overwrites the first', () async {
    final controller = VillageSaveController();
    await controller.save(VillageSaveData(
      boardCells: const ['A'],
      rackCells: const ['B'],
      pool: const [],
      dealtLetters: const ['A', 'B'],
      lastCashedOutScore: 1,
    ));
    await controller.save(VillageSaveData(
      boardCells: const ['Z'],
      rackCells: const ['Y'],
      pool: const [],
      dealtLetters: const ['Z', 'Y'],
      lastCashedOutScore: 99,
    ));

    final loaded = await controller.load();
    expect(loaded!.boardCells, ['Z']);
    expect(loaded.lastCashedOutScore, 99);
  });

  test('corrupt saved data is treated as no save rather than throwing', () async {
    SharedPreferences.setMockInitialValues({'infiniteEstateVillageSave': 'not valid json'});
    final controller = VillageSaveController();
    expect(await controller.load(), isNull);
  });

  // Later specs change no saved data: a save in the current (spec-01,
  // version 2) shape must keep loading and restoring exactly.
  test('a version-2 save loads and restores with the same board, rack and pool', () async {
    SharedPreferences.setMockInitialValues({
      'infiniteEstateVillageSave': jsonEncode({
        'boardCells': ['W', 'E', 'L', 'L', null, null],
        'rackCells': ['A', 'B', 'C'],
        'pool': ['D', 'E'],
        'dealtLetters': ['W', 'E', 'L', 'L', 'A', 'B', 'C'],
        'lastCashedOutScore': 7,
        'reachedLandmarks': [4],
        'discoveredWords': ['WELL'],
        'saveVersion': 2,
      }),
    });
    final loaded = (await VillageSaveController().load())!;
    expect(loaded.saveVersion, 2);

    final container = ProviderContainer(overrides: [
      gridConfigProvider.overrideWithValue(const GridConfig(boardWidth: 6, boardHeight: 1, rackSize: 3)),
    ]);
    addTearDown(container.dispose);
    container.read(gridGameControllerProvider.notifier).restoreState(
          boardCells: loaded.boardCells,
          rackCells: loaded.rackCells,
          pool: loaded.pool,
          dealtLetters: loaded.dealtLetters,
        );
    final state = container.read(gridGameControllerProvider);
    expect(state.boardCells, ['W', 'E', 'L', 'L', null, null]);
    expect(state.rackCells, ['A', 'B', 'C']);
    expect(state.pool, ['D', 'E']);
    expect(loaded.reachedLandmarks, {4});
    expect(loaded.discoveredWords, {'WELL'});
  });
}
