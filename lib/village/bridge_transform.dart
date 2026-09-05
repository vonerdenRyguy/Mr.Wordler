import 'package:flutter/widgets.dart' show Matrix4, Size;

// Bridge structure ability: computes the InteractiveViewer transform that
// centers a given board cell in the viewport at `scale`. Pure and testable
// on its own -- no BuildContext/RenderBox needed, just the viewport size a
// real screen would report at the moment of the jump.
//
// Infinite Estate's board is rendered lazily (InteractiveViewer.builder)
// at a fixed pixel size per cell, not scaled to fit the viewport, so a
// cell's center in *untransformed* content coordinates is simply
// `((col + 0.5) * cellSize, (row + 0.5) * cellSize)` -- no letterboxing
// math needed.
//
// InteractiveViewer builds its transform as a translate-then-scale, so a
// content-space point `p` lands at `scale * p + translation` in the
// viewport. Solving for the translation that sends the cell's center to
// the viewport's center gives the matrix below.
Matrix4 computeCenterTransform({
  required Size viewportSize,
  required int boardIndex,
  required int boardWidth,
  required double cellSize,
  required double scale,
}) {
  final col = boardIndex % boardWidth;
  final row = boardIndex ~/ boardWidth;
  final cellCenterX = (col + 0.5) * cellSize;
  final cellCenterY = (row + 0.5) * cellSize;

  final translateX = viewportSize.width / 2 - scale * cellCenterX;
  final translateY = viewportSize.height / 2 - scale * cellCenterY;

  return Matrix4.identity()
    ..translate(translateX, translateY)
    ..scale(scale);
}
