import 'dart:math';

// Landmark spots: fixed board positions, spaced at increasing distance
// from the village's origin (the board's center), marked visually before
// anything is built on them. Reaching one (placing a letter there) is a
// one-time, always-positive event -- see InfiniteEstateScreen for what
// happens when one is reached.
//
// Spacing/count is a formula, not per-tile hardcoding, so it's easy to
// tune: `_ringDistances` sets how far out each successive landmark sits
// (increasing gaps => landmarks get rarer/further apart the more you've
// already found, which is what makes exploring outward keep surfacing
// new goals rather than front-loading them all close to home), and the
// golden-angle step spreads them around the village instead of lining
// them up in one direction.
const List<double> _ringDistances = [4, 9, 15, 22, 28];
const double _goldenAngle = 2.399963; // radians; spreads points evenly around a circle

List<int> landmarkBoardIndices(int boardWidth, int boardHeight) {
  final centerRow = boardHeight ~/ 2;
  final centerCol = boardWidth ~/ 2;
  final maxRadius = (min(boardWidth, boardHeight) / 2) - 2; // stay inside the bounded board

  final indices = <int>[];
  double angle = 0.6;
  for (final rawDistance in _ringDistances) {
    final distance = rawDistance.clamp(0, maxRadius);
    final row = (centerRow + distance * sin(angle)).round().clamp(0, boardHeight - 1);
    final col = (centerCol + distance * cos(angle)).round().clamp(0, boardWidth - 1);
    indices.add(row * boardWidth + col);
    angle += _goldenAngle;
  }
  return indices;
}
