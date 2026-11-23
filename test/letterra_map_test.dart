import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/island_map.dart';
import 'package:namer_app/letterra/planet.dart';

const _centre = 250 * 500 + 250;

Map<String, int> _counts(IslandMap m) {
  final out = <String, int>{};
  for (final s in m.specials) {
    final k = '${m.ringAtIndex(s.cell).name}/${s.kind.name}';
    out[k] = (out[k] ?? 0) + 1;
  }
  return out;
}

void main() {
  final legacy = IslandMap(seed: 7, homes: const [_centre]);
  final a = IslandMap.letterra(seed: 7);

  test('rings follow the bands', () {
    Ring at(int dRow, int dCol) => a.ringAt(250 + dRow, 250 + dCol);
    expect(at(120, 0), Ring.meadow); // shore
    expect(at(100, 0), Ring.meadow);
    expect(at(80, 0), Ring.forest);
    expect(at(66, 0), Ring.river);
    expect(at(50, 0), Ring.hills);
    expect(at(30, 0), Ring.mountains);
    expect(at(10, 0), Ring.coast); // Cloud Cap: no fog clearing yet
    expect(at(130, 0), Ring.coast); // the Deep
    expect(a.isWater(250 + 66, 250), isTrue);
  });

  test('same seed and slots give the same specials', () {
    final b = IslandMap.letterra(seed: 7);
    expect(b.specials.map((s) => '${s.id}:${s.cell}').toList(),
        a.specials.map((s) => '${s.id}:${s.cell}').toList());
  });

  test('ids and kinds match the old island, in the same order', () {
    expect(a.specials.length, legacy.specials.length);
    for (var i = 0; i < a.specials.length; i++) {
      expect(a.specials[i].id, legacy.specials[i].id);
      expect(a.specials[i].kind, legacy.specials[i].kind);
    }
  });

  test('band counts match spec-15 per ring', () {
    expect(_counts(a), _counts(legacy));
  });

  test('no special inside any wedge (the near villager aside)', () {
    for (final s in a.specials) {
      if (s.id == 'v0') continue;
      expect(inAnyWedge(s.cell ~/ 500, s.cell % 500), isFalse, reason: s.id);
    }
  });

  test('only the first villager depends on the slot', () {
    final b = IslandMap.letterra(seed: 7, slot: 4, takenSlots: {0, 4});
    for (var i = 0; i < a.specials.length; i++) {
      if (a.specials[i].id == 'v0') {
        expect(b.specials[i].cell, isNot(a.specials[i].cell));
      } else {
        expect(b.specials[i].cell, a.specials[i].cell);
      }
    }
  });

  test('the first villager is 4-8 from your harbor, on land', () {
    for (final slot in [0, 4, 2, 6]) {
      final m = IslandMap.letterra(seed: 7, slot: slot);
      final h = harborCell(slot);
      final v = m.villagers.first;
      final d = math.max((v.cell ~/ 500 - h ~/ 500).abs(),
          (v.cell % 500 - h % 500).abs());
      expect(d, inInclusiveRange(4, 8), reason: 'slot $slot');
      expect(m.ringAtIndex(v.cell), isNot(Ring.coast));
      expect(isBay(v.cell ~/ 500, v.cell % 500, {slot}), isFalse);
    }
  });

  test('reachable cells exclude bays', () {
    final alone = a.reachableCellCount;
    final all8 = IslandMap.letterra(seed: 7, takenSlots: takenSlotsFor(8));
    expect(all8.reachableCellCount, greaterThan(alone));
  });
}
