import 'package:flutter/widgets.dart' show Matrix4, Size;

// Bridge structure ability: computes the InteractiveViewer transform that
// centers a given board cell in the viewport at `scale`. Pure and testable
// on its own -- no BuildContext/RenderBox needed, just the viewport size a
// real screen would report at the moment of the jump.
//
// Derived from InteractiveViewer's `constrained: true` default (the one
// every GridBoardView/VillageBoardView uses): the child is laid out at
// exactly the viewport's size before any transform is applied, and the
// board sits centered inside that as the largest square that fits (via
// AspectRatio + Center), letterboxed on whichever axis is wider. Infinite
// Estate's board is always square (boardWidth == boardHeight), which this
// assumes -- it's not a general-purpose viewer helper.
//
// In *untransformed* child coordinates, cell (col, row) is centered at:
//   boardOffset + (col + 0.5, row + 0.5) * cellSize
// where boardPixelSize = min(viewport.width, viewport.height) and
// boardOffset centers that square within the (possibly non-square)
// viewport.
//
// InteractiveViewer builds its transform as a translate-then-scale, so a
// child-space point `p` lands at `scale * p + translation` in the
// viewport. Solving for the translation that sends the cell's center to
// the viewport's center gives the matrix below.
Matrix4 computeCenterTransform({
  required Size viewportSize,
  required int boardIndex,
  required int boardWidth,
  required double scale,
}) {
  final boardPixelSize =
      viewportSize.width < viewportSize.height ? viewportSize.width : viewportSize.height;
  final boardOffsetX = (viewportSize.width - boardPixelSize) / 2;
  final boardOffsetY = (viewportSize.height - boardPixelSize) / 2;
  final cellSize = boardPixelSize / boardWidth;

  final col = boardIndex % boardWidth;
  final row = boardIndex ~/ boardWidth;
  final cellCenterX = boardOffsetX + (col + 0.5) * cellSize;
  final cellCenterY = boardOffsetY + (row + 0.5) * cellSize;

  final translateX = viewportSize.width / 2 - scale * cellCenterX;
  final translateY = viewportSize.height / 2 - scale * cellCenterY;

  return Matrix4.identity()
    ..translate(translateX, translateY)
    ..scale(scale);
}
