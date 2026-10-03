import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/village/bridge_transform.dart';
import 'package:namer_app/village/iso_math.dart';

void main() {
  const grid = IsoGrid(boardWidth: 500, boardHeight: 500);

  test('projecting a cell and inverting gives the same cell', () {
    final random = Random(4);
    for (int i = 0; i < 200; i++) {
      final r = random.nextInt(500);
      final c = random.nextInt(500);
      expect(grid.cellAt(grid.ground(r, c)), (r: r, c: c));
    }
  });

  test('across neighbors step down-right, down neighbors step down-left', () {
    final base = grid.ground(10, 10);
    expect(grid.ground(10, 11) - base, const Offset(isoTileW / 2, isoTileH / 2));
    expect(grid.ground(11, 10) - base, const Offset(-isoTileW / 2, isoTileH / 2));
  });

  test('every ground point is on the positive side of the content', () {
    for (final cell in [(0, 0), (0, 499), (499, 0), (499, 499)]) {
      final g = grid.ground(cell.$1, cell.$2);
      expect(g.dx, greaterThanOrEqualTo(0));
      expect(g.dy, greaterThanOrEqualTo(0));
      expect(g.dx, lessThanOrEqualTo(grid.contentSize.width));
      expect(g.dy, lessThanOrEqualTo(grid.contentSize.height));
    }
  });

  test('a point off the board is no cell', () {
    expect(grid.cellAt(const Offset(-500, -500)), isNull);
  });

  test('Words, then Village, then Words lands on the same cell', () {
    const viewport = Size(390, 520);
    const cellSize = 44.0;
    for (final cell in [(250, 250), (3, 400), (499, 0), (120, 77)]) {
      final flat = computeCenterTransform(
        viewportSize: viewport,
        boardIndex: cell.$1 * 500 + cell.$2,
        boardWidth: 500,
        cellSize: cellSize,
        scale: 1.3,
      );
      final fromFlat = centerCellOfFlatView(flat, viewport, cellSize, boardWidth: 500, boardHeight: 500);
      expect(fromFlat, (r: cell.$1, c: cell.$2));

      final iso = isoTransformCenteredOn(fromFlat.r, fromFlat.c, viewport, transformScale(flat), grid);
      expect(transformScale(iso), closeTo(1.3, 1e-9));
      final fromIso = centerCellOfIsoView(iso, viewport, grid);
      expect(fromIso, (r: cell.$1, c: cell.$2));

      final back = computeCenterTransform(
        viewportSize: viewport,
        boardIndex: fromIso.r * 500 + fromIso.c,
        boardWidth: 500,
        cellSize: cellSize,
        scale: transformScale(iso),
      );
      expect(centerCellOfFlatView(back, viewport, cellSize, boardWidth: 500, boardHeight: 500), (r: cell.$1, c: cell.$2));
    }
  });
}
