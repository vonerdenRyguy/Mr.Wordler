import 'dart:math' as math;

import 'globe_painter.dart' show lonDelta;
import 'planet.dart';

/// A village's port (spec-18b): a pier running out to sea from its shore with
/// a boat beside it. It is only a picture on sea squares, which never hold
/// letters, so it covers and moves nothing and is in no save.
class Port {
  const Port(this.angle, this.pier, this.boat);

  /// Its direction from the Lantern.
  final double angle;

  /// Board squares from the shore outward; a lamp stands on the first and the
  /// middle one and a flag on the last.
  final List<int> pier;
  final int boat;

  int get flag => pier.last;
}

/// Where the port of the village at harbor [slot] faces: the middle of its
/// [letters], kept inside its own harbor's wedge.
double portAngle(int slot, Iterable<int> letters) {
  final home = slotAngle(slot);
  var row = 0.0, col = 0.0;
  for (final i in letters) {
    row += i ~/ kPlanetBoard - kLanternRow;
    col += i % kPlanetBoard - kLanternCol;
  }
  if (row == 0 && col == 0) return home;
  const most = (kBayHalfAngleDegrees - 4) * math.pi / 180;
  return home + lonDelta(home, math.atan2(col, row)).clamp(-most, most);
}

Port portFor(int slot, Iterable<int> letters) {
  final a = portAngle(slot, letters);
  int at(double d, double side) =>
      (kLanternRow + d * math.cos(a) - side * math.sin(a)).round() * kPlanetBoard +
      (kLanternCol + d * math.sin(a) + side * math.cos(a)).round();
  final pier = <int>[];
  for (var d = 124.0; pier.length < 5; d += 0.5) {
    final i = at(d, 0);
    if (!pier.contains(i) && bandAt(i ~/ kPlanetBoard, i % kPlanetBoard) == Band.deep) pier.add(i);
  }
  return Port(a, pier, at(129, 2.2));
}
