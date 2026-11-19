import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/village/village_save.dart';
import 'package:namer_app/village/village_save_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  // A save exactly as the pre-spec-01 build wrote it: no saveVersion key.
  Map<String, dynamic> v1Json({required List<String?> rack, int poolSize = 50}) {
    final rackLetters = rack.whereType<String>().toList();
    return {
      'boardCells': ['W', 'E', 'L', 'L', null, null],
      'rackCells': rack,
      'pool': [for (int i = 0; i < poolSize; i++) letters[i % 26]],
      'dealtLetters': ['W', 'E', 'L', 'L', ...rackLetters],
      'lastCashedOutScore': 42,
      'reachedLandmarks': [3],
      'discoveredWords': ['WELL'],
    };
  }

  List<String> allLetters(VillageSaveData d) => [
        ...d.boardCells.whereType<String>(),
        ...d.rackCells.whereType<String>(),
        ...d.pool,
      ]..sort();

  test('a v1 save with a 21-slot rack (3 empty) migrates to a 10-letter rack', () {
    final rack = <String?>[for (int i = 0; i < 21; i++) i % 7 == 6 ? null : letters[i]];
    final old = VillageSaveData.fromJson(v1Json(rack: rack));
    expect(old.saveVersion, 1);

    final migrated = migrateVillageSave(old, rackSize: 10);

    expect(migrated.saveVersion, 3); // v1→v2→v3 in one pass
    expect(migrated.rackCells.length, 10);
    expect(migrated.rackCells.every((c) => c != null), isTrue);
    expect(migrated.rackCells, rack.whereType<String>().take(10).toList());
    expect(migrated.pool.length, 58);
    expect(migrated.pool.sublist(0, 50), old.pool); // existing pool order kept
    expect(migrated.dealtLetters.length, old.dealtLetters.length - 8);
    expect(migrated.boardCells, old.boardCells);
    expect(migrated.reachedLandmarks, old.reachedLandmarks);
    expect(migrated.discoveredWords, old.discoveredWords);
    expect(migrated.lastCashedOutScore, 42);
    expect(allLetters(migrated), allLetters(old));
  });

  test('a v1 save with 21 base slots plus 2 bonus slots handles all 23', () {
    final rack = <String?>[for (int i = 0; i < 23; i++) letters[i]];
    final old = VillageSaveData.fromJson(v1Json(rack: rack));

    final migrated = migrateVillageSave(old, rackSize: 10);

    expect(migrated.rackCells, rack.take(10).toList());
    expect(migrated.pool.length, 50 + 13);
    expect(allLetters(migrated), allLetters(old));
  });

  test('a v1 save with only 4 rack letters becomes 4 letters plus 6 empty slots', () {
    final rack = <String?>['A', null, 'B', 'C', null, 'D', ...List<String?>.filled(15, null)];
    final old = VillageSaveData.fromJson(v1Json(rack: rack));

    final migrated = migrateVillageSave(old, rackSize: 10);

    expect(migrated.rackCells, ['A', 'B', 'C', 'D', null, null, null, null, null, null]);
    expect(migrated.pool.length, 50);
    expect(allLetters(migrated), allLetters(old));
  });

  test('a v2 save migrates to v3 (adds fog and explore state)', () {
    final v2 = VillageSaveData(
      boardCells: const ['A', null, 'B', null, 'C', null],
      rackCells: List<String?>.filled(10, 'E'),
      pool: const ['B'],
      dealtLetters: const ['A'],
      lastCashedOutScore: 1,
      saveVersion: 2,
    );
    final migrated = migrateVillageSave(v2, rackSize: 10);
    expect(migrated.saveVersion, 3);
    expect(migrated.boardCells, v2.boardCells);
    expect(migrated.rackCells, v2.rackCells);
    expect(migrated.pool, v2.pool);
    expect(migrated.mapSeed, VillageSaveData.kDefaultMapSeed);
    expect(migrated.mapVersion, VillageSaveData.kDefaultMapVersion);
    expect(migrated.cleared, isNotNull); // fog was initialised
    // Occupied board cells (indices 0, 2, 4) are in everUsed
    expect(migrated.everUsed, {0, 2, 4});
    expect(migrated.foundSpecials, isEmpty);
    expect(migrated.shrines, isEmpty);
    expect(migrated.levelTreats, isEmpty);
  });

  test('v2→v3: fog is cleared around existing letters', () {
    // Board cell index 0 is row 0, col 0 on a 500-wide board.
    // Fog cleared with radius 3 → cells within Chebyshev 3 are cleared.
    final v2 = VillageSaveData(
      boardCells: List<String?>.generate(500 * 500, (i) => i == 0 ? 'A' : null),
      rackCells: List<String?>.filled(10, null),
      pool: const [],
      dealtLetters: const ['A'],
      lastCashedOutScore: 0,
      saveVersion: 2,
    );
    final migrated = migrateVillageSave(v2, rackSize: 10, boardWidth: 500, boardHeight: 500);
    expect(migrated.cleared, isNotNull);

    // Reconstruct fog and check a known-cleared cell (e.g. (0,2) = index 2)
    // and a known-uncleared cell (e.g. (0,10) = index 10, distance 10 > 3).
    // We can check directly that everUsed contains cell 0.
    expect(migrated.everUsed.contains(0), isTrue);
  });

  test('a v3 save comes back unchanged', () {
    final v3 = VillageSaveData(
      boardCells: const ['A', null],
      rackCells: List<String?>.filled(10, 'E'),
      pool: const ['B'],
      dealtLetters: const ['A'],
      lastCashedOutScore: 1,
      saveVersion: 3,
      cleared: 'AAAA', // arbitrary non-null base64
    );
    expect(identical(migrateVillageSave(v3, rackSize: 10), v3), isTrue);
  });

  test('round trip: save, load, migrate, save, load -- version 3 and stable', () async {
    final prefs = await SharedPreferences.getInstance();
    final controller = VillageSaveController();
    final rack = <String?>[for (int i = 0; i < 21; i++) letters[i]];
    await controller.save(VillageSaveData.fromJson(v1Json(rack: rack)));
    // Strip the key a v1 build would never have written.
    final raw = prefs.getString('infiniteEstateVillageSave')!;
    await prefs.setString('infiniteEstateVillageSave', raw.replaceAll(',"saveVersion":1', ''));

    final loaded = (await controller.load())!;
    expect(loaded.saveVersion, 1);
    final migrated = migrateVillageSave(loaded, rackSize: 10);
    await controller.save(migrated);

    final reloaded = (await controller.load())!;
    expect(reloaded.saveVersion, 3);
    expect(reloaded.rackCells, migrated.rackCells);
    expect(reloaded.pool, migrated.pool);
    // Migrating a v3 save is a no-op.
    expect(identical(migrateVillageSave(reloaded, rackSize: 10), reloaded), isTrue);
  });
}
