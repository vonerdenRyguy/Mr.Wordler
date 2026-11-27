import 'package:flutter/widgets.dart' show Matrix4, Size;
import 'package:vector_math/vector_math_64.dart' show Vector3;

// The Words view's camera: which square is in the middle, and the zoom.

/// The board cell at the center of the flat Words view.
({int r, int c}) centerCellOfFlatView(
  Matrix4 m,
  Size viewport,
  double cellSize, {
  required int boardWidth,
  required int boardHeight,
}) {
  final v = Matrix4.inverted(m).transform3(Vector3(viewport.width / 2, viewport.height / 2, 0));
  return (
    r: (v.y / cellSize).floor().clamp(0, boardHeight - 1),
    c: (v.x / cellSize).floor().clamp(0, boardWidth - 1),
  );
}

/// The zoom of an InteractiveViewer transform.
double transformScale(Matrix4 m) => m.getMaxScaleOnAxis();
