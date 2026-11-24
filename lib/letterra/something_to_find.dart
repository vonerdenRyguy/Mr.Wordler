import '../explore/explore_rules.dart' show minLength;
import '../explore/island_map.dart';
import '../settings/word_level.dart';
import 'globe_painter.dart' show reachName, reachOfBand;
import 'planet.dart';

/// The one thing that glows in planet mode (spec-18b, J321): the nearest
/// special not found yet. It never says what it is.
class SomethingToFind {
  const SomethingToFind(this.cell, this.squares, this.minLength);

  final int cell;

  /// Squares from your nearest letter, counted along rows and columns.
  final int squares;
  final int minLength;

  String get region => reachName(reachOfBand(bandAt(cell ~/ kPlanetBoard, cell % kPlanetBoard)));
}

/// The nearest of [unfound] to [letters] (or to the harbor while there are
/// none); null when there is nothing left that a word can reach.
SomethingToFind? somethingToFind({
  required IslandMap map,
  required Iterable<int> unfound,
  required Iterable<int> letters,
  required WordLevel level,
}) {
  final from = letters.isEmpty ? [harborCell(map.slot)] : letters.toList();
  int? best;
  var bestD = 1 << 30;
  for (final cell in unfound) {
    if (map.isSeaIndex(cell) || map.ringAtIndex(cell) == Ring.coast) continue;
    final r = cell ~/ kPlanetBoard, c = cell % kPlanetBoard;
    for (final i in from) {
      final d = (i ~/ kPlanetBoard - r).abs() + (i % kPlanetBoard - c).abs();
      if (d < bestD) {
        bestD = d;
        best = cell;
      }
    }
  }
  if (best == null) return null;
  return SomethingToFind(best, bestD, minLength(map.ringAtIndex(best), level));
}
