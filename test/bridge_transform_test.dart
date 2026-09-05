import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/village/bridge_transform.dart';

void main() {
  test('centers the top-left cell of a square viewport', () {
    final transform = computeCenterTransform(
      viewportSize: const Size(300, 300),
      boardIndex: 0,
      boardWidth: 60,
      cellSize: 40,
      scale: 1.0,
    );
    // cell 0 center = (20, 20). translation = viewportCenter - scale * cellCenter.
    final translation = transform.getTranslation();
    expect(translation.x, closeTo(130.0, 0.001));
    expect(translation.y, closeTo(130.0, 0.001));
  });

  test('scale multiplies the translation needed to re-center', () {
    final transform = computeCenterTransform(
      viewportSize: const Size(300, 300),
      boardIndex: 0,
      boardWidth: 60,
      cellSize: 40,
      scale: 2.0,
    );
    final translation = transform.getTranslation();
    // translation = 150 - 2.0 * 20 = 110.
    expect(translation.x, closeTo(110.0, 0.001));
    expect(translation.y, closeTo(110.0, 0.001));
  });

  test('property: the transform always maps the cell center to the viewport center', () {
    const cases = [
      (viewport: Size(400, 300), boardIndex: 17, boardWidth: 20, cellSize: 30.0, scale: 1.5),
      (viewport: Size(250, 600), boardIndex: 399, boardWidth: 20, cellSize: 44.0, scale: 0.5),
      (viewport: Size(500, 500), boardIndex: 0, boardWidth: 500, cellSize: 44.0, scale: 3.0),
    ];
    for (final c in cases) {
      final col = c.boardIndex % c.boardWidth;
      final row = c.boardIndex ~/ c.boardWidth;
      final cellCenter = Offset((col + 0.5) * c.cellSize, (row + 0.5) * c.cellSize);

      final transform = computeCenterTransform(
        viewportSize: c.viewport,
        boardIndex: c.boardIndex,
        boardWidth: c.boardWidth,
        cellSize: c.cellSize,
        scale: c.scale,
      );
      final mapped = MatrixUtils.transformPoint(transform, cellCenter);
      expect(mapped.dx, closeTo(c.viewport.width / 2, 0.001));
      expect(mapped.dy, closeTo(c.viewport.height / 2, 0.001));
    }
  });
}
