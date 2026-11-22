import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/letterra/planet.dart';

Band _at(int dRow, int dCol) => bandAt(kLanternRow + dRow, kLanternCol + dCol);

void main() {
  test('band boundaries along an axis', () {
    final edges = {
      Band.northPeak: [0, 6],
      Band.cloudCap: [7, 20],
      Band.echoMountains: [21, 44],
      Band.ruinHills: [45, 64],
      Band.ribbonRiver: [65, 68],
      Band.whisperWoods: [69, 94],
      Band.meadow: [95, 116],
      Band.sunnyShore: [117, 124],
    };
    edges.forEach((band, range) {
      expect(_at(range[0], 0), band, reason: '${band.name} inner edge');
      expect(_at(0, range[1]), band, reason: '${band.name} outer edge');
    });
    expect(_at(125, 0), Band.deep);
  });

  test('bands are round, not square', () {
    expect(_at(90, 90), Band.deep); // Chebyshev 90, Euclidean ~127
    expect(_at(60, 60), Band.whisperWoods); // ~85 away
    expect(_at(75, 75), Band.meadow); // ~106 away
  });

  test('off the board is the Deep', () {
    expect(bandAt(-1, 10), Band.deep);
    expect(bandAt(10, 500), Band.deep);
  });

  test('all 8 harbors sit on the Sunny Shore, distinct', () {
    final cells = <int>{};
    for (var s = 0; s < kHarborSlots; s++) {
      final h = harborCell(s);
      cells.add(h);
      expect(bandAt(h ~/ kPlanetBoard, h % kPlanetBoard), Band.sunnyShore,
          reason: 'slot $s');
    }
    expect(cells.length, 8);
  });

  test('slot 0 is south of the Lantern, slot 4 north', () {
    final h0 = harborCell(0), h4 = harborCell(4);
    expect(h0 ~/ kPlanetBoard, kLanternRow + kHarborDistance);
    expect(h0 % kPlanetBoard, kLanternCol);
    expect(h4 ~/ kPlanetBoard, kLanternRow - kHarborDistance);
  });

  test('slot order for 1-8 members', () {
    expect(kSlotOrder, [0, 4, 2, 6, 1, 5, 3, 7]);
    expect(takenSlotsFor(1), {0});
    expect(takenSlotsFor(2), {0, 4});
    expect(takenSlotsFor(3), {0, 4, 2});
    expect(takenSlotsFor(4), {0, 4, 2, 6});
    expect(takenSlotsFor(8).length, 8);
    expect(slotForJoinIndex(2), 2);
    expect(slotForJoinIndex(8), isNull);
  });

  test('bays block only the wedge of empty slots, in Shore and Meadow', () {
    final alone = takenSlotsFor(1);
    final own = harborCell(0), other = harborCell(4);
    expect(isBay(own ~/ kPlanetBoard, own % kPlanetBoard, alone), isFalse);
    expect(isBay(other ~/ kPlanetBoard, other % kPlanetBoard, alone), isTrue);
    var bays = 0;
    for (var s = 0; s < kHarborSlots; s++) {
      final h = harborCell(s);
      if (isBay(h ~/ kPlanetBoard, h % kPlanetBoard, alone)) bays++;
    }
    expect(bays, 7);
    expect(isBay(other ~/ kPlanetBoard, other % kPlanetBoard, takenSlotsFor(2)),
        isFalse);
    // Not in the Woods, even straight above a bay.
    expect(isBay(kLanternRow - 80, kLanternCol, alone), isFalse);
    // Meadow in a bay's wedge is sea.
    expect(isBay(kLanternRow - 100, kLanternCol, alone), isTrue);
    // ~22 degrees off slot 0 is between wedges (16 degrees).
    expect(inAnyWedge(kLanternRow + 109, kLanternCol + 45), isFalse);
  });
}
