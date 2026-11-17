import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/word_runs.dart';
import 'package:namer_app/village/iso_math.dart';
import 'package:namer_app/village/iso_village_view.dart';
import 'package:namer_app/village/structures.dart';
import 'package:namer_app/village/village_art.dart';

void main() {
  const grid = IsoGrid(boardWidth: 10, boardHeight: 10);
  const meta = SpriteMeta(
    anchorX: 200,
    anchorY: 400,
    width: 400,
    height: 440,
    spritePath: 'assets/village/buildings/well.png',
    cardPath: 'assets/village/cards/well.png',
  );

  VillageScene scene() {
    final board = List<String?>.filled(100, null);
    // WELL across row 5, cols 2-5; a path word CAT across row 8.
    for (final (i, l) in [(52, 'W'), (53, 'E'), (54, 'L'), (55, 'L'), (82, 'C'), (83, 'A'), (84, 'T')]) {
      board[i] = l;
    }
    return VillageScene(
      grid: grid,
      boardCells: board,
      structures: computeStructures(const [WordRun('WELL', [52, 53, 54, 55], true)]),
      landmarkIndices: const {},
      spriteMeta: const {'WELL': meta},
    );
  }

  test('a building rectangle wins over the cell under it', () {
    final s = scene();
    final rect = s.buildingRect(s.structures.single)!;
    final hit = hitTestVillage(rect.center, s);
    expect(hit, isA<BuildingHit>());
  });

  test('a transparent sprite pixel falls through to what is behind', () {
    final s = scene();
    // The sprite covers the WELL letters; with every pixel transparent the
    // tap reaches the block below.
    final ground = s.groundOf(53) - const Offset(0, isoBuildingLift);
    expect(hitTestVillage(ground, s), isA<BuildingHit>());
    final hit = hitTestVillage(ground, s, opaque: (_, __, ___) => false);
    expect(hit, isA<CellHit>());
    expect((hit as CellHit).index, 53);
  });

  test("a building's lot cell hits its own cell", () {
    final s = scene();
    final top = s.groundOf(55) - const Offset(0, isoBuildingLift);
    final hit = hitTestVillage(top, s, opaque: (_, __, ___) => false);
    expect((hit as CellHit).index, 55);
  });

  test('a path letter hits its cell, empty grass hits nothing', () {
    final s = scene();
    expect((hitTestVillage(s.groundOf(83), s) as CellHit).index, 83);
    expect(hitTestVillage(s.groundOf(99), s), isA<NoHit>());
  });
}
