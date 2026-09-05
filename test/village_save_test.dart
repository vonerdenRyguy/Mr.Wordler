import 'package:flutter_test/flutter_test.dart';
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
}
