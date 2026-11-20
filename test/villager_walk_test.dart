// Villagers walk only along word slabs, and stand still with Reduce motion (spec-16).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/village/iso_math.dart';
import 'package:namer_app/village/iso_village_view.dart';
import 'package:namer_app/village/structures.dart';
import 'package:namer_app/villagers/walkers.dart';

const _w = 500;
int _i(int r, int c) => r * _w + c;

void main() {
  // A word across row 100, cols 100..105 and one down col 103, rows 100..104.
  final slabs = <int>{
    for (var c = 100; c <= 105; c++) _i(100, c),
    for (var r = 101; r <= 104; r++) _i(r, 103),
  };

  test('a villager is put on the nearest slab and only ever steps between slabs', () {
    final walkers = VillagerWalkers(seed: 1);
    walkers.sync({'v0': _i(98, 100)}, slabs); // their home square is on grass
    expect(slabs.contains(walkers.cellOf('v0')), isTrue);
    var last = walkers.cellOf('v0')!;
    final seen = <int>{last};
    for (var i = 0; i < 4000; i++) {
      walkers.tick(0.1);
      final p = walkers.positionOf('v0');
      // Always on the line between two slabs: at least one of the two
      // cells it is between is a slab, and the position stays on slab rows/cols.
      final r = p.r.round(), c = p.c.round();
      final onSlab = slabs.contains(_i(r, c));
      expect(onSlab, isTrue, reason: 'at ${p.r},${p.c}');
      final cur = walkers.cellOf('v0')!;
      if (cur != last) {
        expect((cur ~/ _w - last ~/ _w).abs() + (cur % _w - last % _w).abs(), 1);
        last = cur;
        seen.add(cur);
      }
    }
    expect(seen.length, greaterThan(3)); // they really do wander
  });

  test('when a slab goes away they move to the nearest remaining one', () {
    final walkers = VillagerWalkers(seed: 2);
    walkers.sync({'v0': _i(100, 100)}, slabs);
    final smaller = {_i(100, 105)};
    walkers.sync({'v0': _i(100, 100)}, smaller);
    expect(walkers.cellOf('v0'), _i(100, 105));
  });

  test('nowhere to walk: they stay on their home square', () {
    final walkers = VillagerWalkers();
    walkers.sync({'v0': _i(10, 10)}, const {});
    expect(walkers.cellOf('v0'), isNull);
    final p = walkers.positionOf('v0');
    expect((p.r, p.c), (10.0, 10.0));
    walkers.tick(5);
    expect(walkers.positionOf('v0').r, 10.0);
  });

  VillageScene sceneOf(Map<int, String> letters) {
    final board = List<String?>.filled(_w * _w, null);
    letters.forEach((k, v) => board[k] = v);
    return VillageScene(
        grid: const IsoGrid(boardWidth: _w, boardHeight: _w), boardCells: board, structures: const <BoardStructure>[]);
  }

  Future<VillagerWalkers> pumpView(WidgetTester tester, {required bool reduceMotion}) async {
    final scene = sceneOf({for (final c in slabs) c: 'A'});
    final walkers = VillagerWalkers(seed: 3)..sync({'v0': _i(100, 100)}, scene.walkable);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: SizedBox(
          width: 400,
          height: 600,
          child: IsoVillageView(
            scene: scene,
            walkers: walkers,
            villagers: const [VillagerSprite(id: 'v0', name: 'Pip')],
          ),
        ),
      ),
    ));
    return walkers;
  }

  testWidgets('in Village view they stroll', (tester) async {
    final walkers = await pumpView(tester, reduceMotion: false);
    final start = walkers.positionOf('v0');
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final end = walkers.positionOf('v0');
    expect(walkers.cellOf('v0') != _i(100, 100) || start != end, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with Reduce motion they stand still', (tester) async {
    final walkers = await pumpView(tester, reduceMotion: true);
    final start = walkers.positionOf('v0');
    final cell = walkers.cellOf('v0');
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(walkers.positionOf('v0'), start);
    expect(walkers.cellOf('v0'), cell);
    // A pumpAndSettle would finish: nothing is animating.
    await tester.pumpAndSettle();
  });

  test('tapping a villager is a VillagerHit, ahead of the slab under them', () {
    final scene = sceneOf({for (final c in slabs) c: 'A'});
    final g = scene.groundOf(_i(100, 102)) - const Offset(0, 6);
    final hit = hitTestVillage(g - const Offset(0, 25), scene, villagers: [VillagerSpot('v0', g)]);
    expect(hit, isA<VillagerHit>());
    expect(hitTestVillage(g, scene), isA<CellHit>());
  });
}
