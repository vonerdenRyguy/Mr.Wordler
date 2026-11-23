// spec-18: the globe. Golden-free: projection geometry, board/sphere mapping,
// tap areas, free spinning, zoom and the Hush rule.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/letterra/planet.dart';

const _size = Size(411, 480);

bool _noHush(int r, int c, double lon) => false;

void main() {
  group('projection', () {
    test('your harbor sits low and centred, the Lantern towards the top', () {
      final p = GlobeProjection(size: _size, centerLon: 0, centerLat: 0.42, zoom: 1.25);
      final harbor = p.harborAt(0)!;
      expect(harbor.dx, closeTo(_size.width / 2, 0.5));
      expect(harbor.dy, greaterThan(_size.height / 2));
      expect(p.lantern.dy, lessThan(harbor.dy));
      expect(p.project(math.pi / 2, 0).front, isTrue);
    });

    test('a harbor on the far side is not shown; a neighbour is to the right', () {
      final p = GlobeProjection(size: _size, centerLon: 0, centerLat: 0.42, zoom: 1.25);
      expect(p.harborAt(4), isNull);
      expect(p.harborAt(1)!.dx, greaterThan(_size.width / 2));
    });

    test('spinning to a harbor brings it to the middle', () {
      final p = GlobeProjection(size: _size, centerLon: slotAngle(4), centerLat: 0.42, zoom: 1.25);
      expect(p.harborAt(4)!.dx, closeTo(_size.width / 2, 0.5));
      expect(p.harborAt(0), isNull);
    });

    test('the whole planet fits its box at zoom 1', () {
      const box = Size(390, 600);
      final p = GlobeProjection(size: box, centerLon: 0, centerLat: 0.3, zoom: 1);
      expect(p.radius * 2, lessThanOrEqualTo(box.width));
    });

    test('zooming in makes a board cell bigger, in proportion', () {
      final near = GlobeProjection(size: _size, centerLon: 0, zoom: 6).cellPixels;
      final far = GlobeProjection(size: _size, centerLon: 0, zoom: 2).cellPixels;
      expect(near / far, closeTo(3, 1e-9));
      expect(GlobeProjection(size: _size, centerLon: 0, zoom: kGlobeMaxZoom).cellPixels, greaterThan(15));
    });

    test('every village tap area is at least 48 x 48 at every zoom', () {
      for (final zoom in [1.0, 1.75, 3.0, 7.0]) {
        final p = GlobeProjection(size: const Size(360, 420), centerLon: 0, centerLat: 0.3, zoom: zoom);
        for (var s = 0; s < kHarborSlots; s++) {
          final r = p.villageHit(s);
          if (r == null) continue;
          expect(r.width, greaterThanOrEqualTo(48));
          expect(r.height, greaterThanOrEqualTo(48));
        }
      }
    });

    test('board and sphere agree: the harbor is on the equator at its slot angle', () {
      for (var s = 0; s < kHarborSlots; s++) {
        final h = harborCell(s);
        final row = (h ~/ kPlanetBoard).toDouble(), col = (h % kPlanetBoard).toDouble();
        final ll = boardToSphere(row, col);
        expect(ll.lat.abs(), lessThan(0.02));
        expect(lonDelta(ll.lon, slotAngle(s)).abs(), lessThan(0.02));
        final back = sphereToBoard(ll.lat, ll.lon);
        expect(back.row, closeTo(row, 1e-6));
        expect(back.col, closeTo(col, 1e-6));
      }
      // The Lantern is the North Pole.
      expect(boardToSphere(250, 250).lat, closeTo(math.pi / 2, 1e-9));
    });

    test('magic words are found as exact runs', () {
      int c(int r, int col) => r * kPlanetBoard + col;
      final letters = {
        for (var i = 0; i < 4; i++) c(300, 200 + i): 'WELL'[i],
        for (var i = 0; i < 4; i++) c(301 + i, 205): 'BARN'[i],
        c(310, 210): 'Q',
      };
      final runs = magicRunsOn(letters);
      expect(runs.map((r) => r.word).toSet(), {'WELL', 'BARN'});
    });
  });

  group('the Hush by reach', () {
    test('land above your reach is hushed, below it is clear, sea never', () {
      // Whisper Woods cell straight above slot 0's harbor.
      const woods = kLanternRow + 80;
      expect(bandAt(woods, kLanternCol), Band.whisperWoods);
      expect(hushedByReach(woods, kLanternCol, 1), isTrue); // reached the Meadow
      expect(hushedByReach(woods, kLanternCol, 2), isFalse); // reached the Woods
      expect(hushedByReach(kLanternRow + 130, kLanternCol, 0), isFalse); // the Deep
      expect(reachName(2), 'the Woods');
      expect(reachOfBand(Band.whisperWoods), 2);
    });

    test('lonDelta takes the short way round', () {
      expect(lonDelta(0.1, 2 * math.pi - 0.1), closeTo(-0.2, 1e-9));
      expect(wrapLon(-0.5), closeTo(2 * math.pi - 0.5, 1e-9));
    });
  });

  Widget host({
    required int focus,
    List<int> slots = const [0, 4],
    void Function(int)? onTap,
    void Function(int)? onTurn,
    bool reduce = false,
    Map<int, String> letters = const {},
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: _size.width,
            height: _size.height,
            child: GlobeView(
              villages: [
                for (final s in slots)
                  GlobeVillage(slot: s, name: 'P$s', buildings: const ['WELL'], letters: s == 0 ? letters : const {}),
              ],
              takenSlots: slots.toSet(),
              focusSlot: focus,
              isHushed: _noHush,
              onVillageTap: onTap,
              onTurn: onTurn,
              reduceMotion: reduce,
            ),
          ),
        ),
      );

  testWidgets('tapping your village reports its slot', (tester) async {
    int? tapped;
    await tester.pumpWidget(host(focus: 0, onTap: (s) => tapped = s));
    expect(find.byKey(const ValueKey('globe-village-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('globe-village-4')), findsNothing); // far side
    await tester.tap(find.byKey(const ValueKey('globe-village-0')));
    expect(tapped, 0);
    final size = tester.getSize(find.byKey(const ValueKey('globe-village-0')));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('a drag spins the globe freely and reports the nearest village', (tester) async {
    int? turned;
    await tester.pumpWidget(host(focus: 0, slots: [0, 2, 4], onTurn: (s) => turned = s));
    // Dragging left turns the planet east: the other villages come round.
    await tester.drag(find.byType(GlobeView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(turned, isNotNull);
    expect(turned, isNot(0));
    expect(find.byKey(const ValueKey('globe-village-0')), findsNothing);
  });

  testWidgets('the zoom buttons zoom in and out, and stop at the ends', (tester) async {
    await tester.pumpWidget(host(focus: 0));
    await tester.pumpAndSettle();
    final start = tester.getSize(find.byKey(const ValueKey('globe-village-0')));
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('globe-zoom-in')));
      await tester.pumpAndSettle();
    }
    final big = tester.getSize(find.byKey(const ValueKey('globe-village-0')));
    expect(big.width, greaterThan(start.width));
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byKey(const ValueKey('globe-zoom-out')));
      await tester.pumpAndSettle();
    }
    final small = tester.getSize(find.byKey(const ValueKey('globe-village-0')));
    expect(small.width, lessThan(big.width));
  });

  testWidgets('zoomed right in, the village paints its tiles on the curved surface without error', (tester) async {
    int c(int r, int col) => r * kPlanetBoard + col;
    final letters = {
      for (var i = 0; i < 4; i++) c(364, 248 + i): 'WELL'[i],
      for (var i = 0; i < 4; i++) c(365 + i, 250): 'BARN'[i],
    };
    await tester.pumpWidget(host(focus: 0, letters: letters));
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('globe-zoom-in')));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the focus turns the planet (instantly with Reduce motion)', (tester) async {
    await tester.pumpWidget(host(focus: 0, reduce: true));
    await tester.pumpWidget(host(focus: 4, reduce: true));
    await tester.pump();
    expect(find.byKey(const ValueKey('globe-village-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('globe-village-0')), findsNothing);

    await tester.pumpWidget(host(focus: 0));
    await tester.pumpWidget(host(focus: 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('globe-village-4')), findsOneWidget);
  });
}
