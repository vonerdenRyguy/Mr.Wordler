import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/village/bridge_transform.dart';
import 'package:namer_app/village/village_layout.dart';
import 'package:namer_app/village/words_camera.dart';

void main() {
  test('Words centered on a square reads that square back, at its zoom', () {
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
      expect(centerCellOfFlatView(flat, viewport, cellSize, boardWidth: 500, boardHeight: 500), (r: cell.$1, c: cell.$2));
      expect(transformScale(flat), closeTo(1.3, 1e-9));
    }
  });

  test('villagers walk on ordinary words; with only buildings, on those', () {
    final board = List<String?>.filled(100, null);
    for (final (i, ch) in [(11, 'C'), (12, 'A'), (13, 'T')]) {
      board[i] = ch;
    }
    expect(walkableCells(board, const []), {11, 12, 13});
    expect(lettersCenter(board, 10), (r: 1, c: 2));
    expect(lettersCenter(List<String?>.filled(100, null), 10, emptyCell: 57), (r: 5, c: 7));
  });
}
