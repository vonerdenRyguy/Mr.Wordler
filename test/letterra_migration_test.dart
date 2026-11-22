import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/fog.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/village/village_save.dart';
import 'package:namer_app/village/village_save_migration.dart';
import 'package:namer_app/villagers/village_book.dart';

const _bw = 500;
const _oldHome = 250 * _bw + 250;
int _c(int r, int c) => r * _bw + c;

VillageSaveData _v5() {
  final board = List<String?>.filled(_bw * _bw, null);
  // WELL across the old home, and one letter that will land in the sea.
  for (var i = 0; i < 4; i++) {
    board[_c(250, 250 + i)] = 'WELL'[i];
  }
  board[_c(260, 250)] = 'Q'; // 260+120 = 380: 130 from the Lantern, the Deep
  final fog = FogMap.empty().clearAround([_c(250, 250), _c(260, 250)], radius: 3);
  return VillageSaveData(
    boardCells: board,
    rackCells: List<String?>.filled(10, 'A'),
    pool: const ['B', 'C'],
    dealtLetters: const ['W', 'E', 'L', 'L', 'Q'],
    lastCashedOutScore: 0,
    saveVersion: 5,
    cleared: fog.toBase64(),
    everUsed: {_c(250, 250), _c(260, 250)},
    foundSpecials: const {'s0'},
    villagers: VillagerBook([
      Villager(id: 'v0', name: 'Pip', cell: _c(252, 252), hearts: 3),
    ]),
    tidiedLoose: true,
  );
}

void main() {
  test('every tile lands at its old cell plus the offset', () {
    final m = migrateVillageSave(_v5(), rackSize: 10, planetSlot: 0);
    expect(m.saveVersion, 6);
    expect(m.planetSlot, 0);
    expect(m.migratedFrom, 5);
    final off = harborCell(0) - _oldHome; // (+120, 0)
    expect(off, 120 * _bw);
    for (var i = 0; i < 4; i++) {
      expect(m.boardCells[_c(250, 250 + i) + off], 'WELL'[i]);
      expect(m.boardCells[_c(250, 250 + i)], isNull);
    }
    expect(m.boardCells.whereType<String>().length, 5);
  });

  test('fog and used squares shift with the board', () {
    final m = migrateVillageSave(_v5(), rackSize: 10, planetSlot: 0);
    final fog = FogMap.fromBase64(m.cleared!);
    expect(fog.isCleared(_c(370, 250)), isTrue);
    expect(fog.isCleared(_c(250, 250)), isFalse);
    expect(m.everUsed, {_c(370, 250), _c(380, 250)});
  });

  test('a found chest stays found and a villager keeps home, name, hearts', () {
    final m = migrateVillageSave(_v5(), rackSize: 10, planetSlot: 0);
    expect(m.foundSpecials, {'s0'});
    final v = m.villagers.villagers.single;
    expect(v.name, 'Pip');
    expect(v.hearts, 3);
    expect(v.cell, _c(372, 252));
  });

  test('a tile shifted into the sea is a pier and still counts', () {
    final m = migrateVillageSave(_v5(), rackSize: 10, planetSlot: 0);
    expect(m.boardCells[_c(380, 250)], 'Q');
    expect(bandAt(380, 250), Band.deep);
    expect(m.dealtLetters, contains('Q'));
  });

  test('loading twice changes nothing', () {
    final once = migrateVillageSave(_v5(), rackSize: 10, planetSlot: 0);
    final twice = migrateVillageSave(once, rackSize: 10, planetSlot: 0);
    expect(twice.toJson().toString(), once.toJson().toString());
  });

  test('save v6 round-trips the planet block', () {
    final m = migrateVillageSave(_v5(), rackSize: 10, planetSlot: 0);
    final back = VillageSaveData.fromJson(m.toJson());
    expect(back.planetSlot, 0);
    expect(back.migratedFrom, 5);
    expect(back.saveVersion, 6);
  });

  test('other slots shift to their own harbor', () {
    final m = migrateVillageSave(_v5(), rackSize: 10, planetSlot: 4);
    expect(m.planetSlot, 4);
    expect(m.boardCells[_c(250, 250) - 120 * _bw], 'W');
  });

  test('a letter that would fall off the board goes back to the pool', () {
    final board = List<String?>.filled(_bw * _bw, null);
    board[_c(450, 250)] = 'Z'; // 450 + 120 > 499
    final data = VillageSaveData(
      boardCells: board,
      rackCells: List<String?>.filled(10, null),
      pool: const [],
      dealtLetters: const ['Z'],
      lastCashedOutScore: 0,
      saveVersion: 5,
      tidiedLoose: true,
    );
    final m = migrateVillageSave(data, rackSize: 10, planetSlot: 0);
    expect(m.boardCells.whereType<String>(), isEmpty);
    expect(m.pool, ['Z']);
    expect(m.dealtLetters, isEmpty);
  });
}
