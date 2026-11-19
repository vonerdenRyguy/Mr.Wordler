import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/word_runs.dart';
import 'package:namer_app/village/building_art.dart';
import 'package:namer_app/village/iso_math.dart';
import 'package:namer_app/village/iso_village_view.dart';
import 'package:namer_app/village/magic_word.dart';
import 'package:namer_app/village/structures.dart';

void main() {
  const grid = IsoGrid(boardWidth: 10, boardHeight: 10);

  VillageScene scene() {
    final board = List<String?>.filled(100, null);
    // WELL across row 5, cols 2-5; a path word CAT across row 8.
    for (final (i, l) in [(52, 'W'), (53, 'E'), (54, 'L'), (55, 'L'), (82, 'C'), (83, 'A'), (84, 'T')]) {
      board[i] = l;
    }
    return VillageScene(
      grid: grid,
      boardCells: board,
      structures: computeStructures(const [
        WordRun('WELL', [52, 53, 54, 55], true)
      ]),
    );
  }

  test('the building covers every letter of its word', () {
    final s = scene();
    final well = s.structures.single;
    expect(s.buildingCells(well), [52, 53, 54, 55]);
    for (final i in [52, 53, 54, 55]) {
      // On each letter's block and just above it.
      expect(hitTestVillage(s.groundOf(i) - const Offset(0, isoBlockHeight), s), isA<BuildingHit>());
      expect(hitTestVillage(s.groundOf(i) - const Offset(0, isoBlockHeight + 20), s), isA<BuildingHit>());
    }
    final rect = s.buildingRect(well)!;
    expect(rect.left, lessThan(s.groundOf(52).dx));
    expect(rect.right, greaterThan(s.groundOf(55).dx));
  });

  test('a path letter hits its cell, empty grass hits nothing', () {
    final s = scene();
    expect((hitTestVillage(s.groundOf(83), s) as CellHit).index, 83);
    expect(hitTestVillage(s.groundOf(99), s), isA<NoHit>());
  });

  test('crossing buildings never share a block', () {
    final board = List<String?>.filled(100, null);
    // HOUSE across row 3 cols 1-5; TOWER down col 2 rows 2-6 (O shared).
    const house = WordRun('HOUSE', [31, 32, 33, 34, 35], true);
    const tower = WordRun('TOWER', [22, 32, 42, 52, 62], false);
    for (final run in [house, tower]) {
      for (int i = 0; i < run.positions.length; i++) {
        board[run.positions[i]] = run.word[i];
      }
    }
    final s = VillageScene(
        grid: grid, boardCells: board, structures: computeStructures([house, tower]));
    expect(s.buildingCells(s.structures[0]), [31, 32, 33, 34, 35]);
    // TOWER loses the shared O and keeps the longer side: W, E, R.
    expect(s.buildingCells(s.structures[1]), [42, 52, 62]);
  });

  test('every building paints at every length, across and down', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    Offset p(double c, double r, double z) => grid.ground(r, c) - Offset(0, z);
    for (final def in kMagicWords) {
      for (int n = 3; n <= 7; n++) {
        for (final across in [true, false]) {
          paintBuilding(
            canvas,
            def.word,
            BuildingSpot(c0: 1.5, r0: 1.5, length: n, across: across, z0: isoBlockHeight, k: isoBuildingScale),
            p,
          );
        }
      }
      expect(buildingTopHeight(def.word, 1), greaterThan(0));
    }
    recorder.endRecording().dispose();
  });
}
