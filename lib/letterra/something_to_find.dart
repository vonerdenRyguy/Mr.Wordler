import '../explore/explore_rules.dart' show minLength;
import '../explore/island_map.dart';
import '../settings/word_level.dart';
import 'globe_painter.dart' show reachName, reachOfBand;
import 'planet.dart';

/// Something that glows in planet mode (spec-18b, J321): the nearest special
/// not found yet, or the three nearest with the Shrine of Sight (spec-22). It never says what it is.
class SomethingToFind {
  const SomethingToFind(this.cell, this.squares, this.minLength);

  final int cell;

  /// Squares from your nearest letter, counted along rows and columns.
  final int squares;
  final int minLength;

  String get region => reachName(reachOfBand(bandAt(cell ~/ kPlanetBoard, cell % kPlanetBoard)));
}

/// The [count] nearest of [unfound] to [letters] (or to the harbor while there
/// are none), nearest first; empty when nothing is left that a word can reach.
List<SomethingToFind> thingsToFind({
  required IslandMap map,
  required Iterable<int> unfound,
  required Iterable<int> letters,
  required WordLevel level,
  int count = 1,
}) {
  final from = letters.isEmpty ? [harborCell(map.slot)] : letters.toList();
  final found = <SomethingToFind>[];
  for (final cell in unfound) {
    if (map.isSeaIndex(cell) || map.ringAtIndex(cell) == Ring.coast) continue;
    final r = cell ~/ kPlanetBoard, c = cell % kPlanetBoard;
    var best = 1 << 30;
    for (final i in from) {
      final d = (i ~/ kPlanetBoard - r).abs() + (i % kPlanetBoard - c).abs();
      if (d < best) best = d;
    }
    found.add(SomethingToFind(cell, best, minLength(map.ringAtIndex(cell), level)));
  }
  found.sort((a, b) => a.squares != b.squares ? a.squares.compareTo(b.squares) : a.cell.compareTo(b.cell));
  return found.take(count).toList();
}
