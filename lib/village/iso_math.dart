import 'package:flutter/widgets.dart' show Matrix4, Offset, Size;
import 'package:vector_math/vector_math_64.dart' show Vector3;

// The angled (isometric) Village view's projection: pure math, no widgets.
// Every board cell (row r, col c) keeps its square; it is just drawn as a
// diamond. Across words run down-right on screen, down words down-left.

const double isoTileW = 88;
const double isoTileH = 44;

// Extra height above the board so a tall building on the back row has
// room to draw.
const double isoHeadroom = 200;

class IsoGrid {
  const IsoGrid({required this.boardWidth, required this.boardHeight});

  final int boardWidth;
  final int boardHeight;

  double get originX => boardHeight * isoTileW / 2;
  // Ground of the back-most cell sits below the headroom.
  double get originY => isoTileH / 2 + isoHeadroom;

  Size get contentSize => Size(
        (boardWidth + boardHeight) * isoTileW / 2,
        (boardWidth + boardHeight) * isoTileH / 2 + isoHeadroom,
      );

  /// The ground center of cell (r, c) in content coordinates.
  Offset ground(num r, num c) => Offset(
        (c - r) * isoTileW / 2 + originX,
        (c + r) * isoTileH / 2 + originY,
      );

  /// The (fractional) cell whose ground center is at [p].
  ({double r, double c}) cellAtExact(Offset p) {
    final u = (p.dx - originX) / (isoTileW / 2);
    final v = (p.dy - originY) / (isoTileH / 2);
    return (r: (v - u) / 2, c: (u + v) / 2);
  }

  /// The nearest cell to ground point [p], or null if it's off the board.
  ({int r, int c})? cellAt(Offset p) {
    final exact = cellAtExact(p);
    final r = exact.r.round();
    final c = exact.c.round();
    if (r < 0 || c < 0 || r >= boardHeight || c >= boardWidth) return null;
    return (r: r, c: c);
  }
}

// The content-space point at the middle of the viewport, for an
// InteractiveViewer transform [m] (translate then scale).
Offset _viewportCenterInContent(Matrix4 m, Size viewport) {
  final inverse = Matrix4.inverted(m);
  final v = inverse.transform3(Vector3(viewport.width / 2, viewport.height / 2, 0));
  return Offset(v.x, v.y);
}

double _scaleOf(Matrix4 m) => m.getMaxScaleOnAxis();

/// The board cell at the center of the flat Words view.
({int r, int c}) centerCellOfFlatView(
  Matrix4 m,
  Size viewport,
  double cellSize, {
  required int boardWidth,
  required int boardHeight,
}) {
  final p = _viewportCenterInContent(m, viewport);
  return (
    r: (p.dy / cellSize).floor().clamp(0, boardHeight - 1),
    c: (p.dx / cellSize).floor().clamp(0, boardWidth - 1),
  );
}

/// The board cell at the center of the angled Village view.
({int r, int c}) centerCellOfIsoView(Matrix4 m, Size viewport, IsoGrid grid) {
  final exact = grid.cellAtExact(_viewportCenterInContent(m, viewport));
  return (
    r: exact.r.round().clamp(0, grid.boardHeight - 1),
    c: exact.c.round().clamp(0, grid.boardWidth - 1),
  );
}

/// The Village view transform that puts cell (r, c)'s ground point in the
/// middle of the viewport at [scale].
Matrix4 isoTransformCenteredOn(int r, int c, Size viewport, double scale, IsoGrid grid) {
  final g = grid.ground(r, c);
  return Matrix4.identity()
    ..translate(viewport.width / 2 - scale * g.dx, viewport.height / 2 - scale * g.dy)
    ..scale(scale);
}

/// The zoom of an InteractiveViewer transform, so switching views keeps it.
double transformScale(Matrix4 m) => _scaleOf(m);
