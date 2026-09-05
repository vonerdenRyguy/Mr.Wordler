import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/village/bridge_transform.dart';

void main() {
  test('centers the top-left cell of a square viewport', () {
    final transform = computeCenterTransform(
      viewportSize: const Size(300, 300),
      boardIndex: 0,
      boardWidth: 60,
      scale: 1.0,
    );
    // cellSize = 300 / 60 = 5, cell 0 center = (2.5, 2.5).
    // translation = viewportCenter - scale * cellCenter = (150 - 2.5, 150 - 2.5).
    final translation = transform.getTranslation();
    expect(translation.x, closeTo(147.5, 0.001));
    expect(translation.y, closeTo(147.5, 0.001));
  });

  test('the board center cell needs (roughly) no translation on a square viewport', () {
    // 60x60 board, index for the cell just past center: col=30,row=30 -> center at (5*30.5, 5*30.5) = (152.5,152.5)
    final transform = computeCenterTransform(
      viewportSize: const Size(300, 300),
      boardIndex: 30 * 60 + 30,
      boardWidth: 60,
      scale: 1.0,
    );
    final translation = transform.getTranslation();
    expect(translation.x, closeTo(-2.5, 0.001));
    expect(translation.y, closeTo(-2.5, 0.001));
  });

  test('scale multiplies the translation needed to re-center', () {
    final transform = computeCenterTransform(
      viewportSize: const Size(300, 300),
      boardIndex: 0,
      boardWidth: 60,
      scale: 2.0,
    );
    final translation = transform.getTranslation();
    // translation = 150 - 2.0 * 2.5 = 145.
    expect(translation.x, closeTo(145.0, 0.001));
    expect(translation.y, closeTo(145.0, 0.001));
  });

  test('property: the transform always maps the cell center to the viewport center', () {
    const cases = [
      (viewport: Size(400, 300), boardIndex: 17, boardWidth: 20, scale: 1.5),
      (viewport: Size(250, 600), boardIndex: 399, boardWidth: 20, scale: 0.5),
      (viewport: Size(500, 500), boardIndex: 0, boardWidth: 60, scale: 3.0),
    ];
    for (final c in cases) {
      final boardPixelSize = c.viewport.width < c.viewport.height ? c.viewport.width : c.viewport.height;
      final boardOffsetX = (c.viewport.width - boardPixelSize) / 2;
      final boardOffsetY = (c.viewport.height - boardPixelSize) / 2;
      final cellSize = boardPixelSize / c.boardWidth;
      final col = c.boardIndex % c.boardWidth;
      final row = c.boardIndex ~/ c.boardWidth;
      final cellCenter = Offset(boardOffsetX + (col + 0.5) * cellSize, boardOffsetY + (row + 0.5) * cellSize);

      final transform = computeCenterTransform(
        viewportSize: c.viewport,
        boardIndex: c.boardIndex,
        boardWidth: c.boardWidth,
        scale: c.scale,
      );
      final mapped = MatrixUtils.transformPoint(transform, cellCenter);
      expect(mapped.dx, closeTo(c.viewport.width / 2, 0.001));
      expect(mapped.dy, closeTo(c.viewport.height / 2, 0.001));
    }
  });
}
