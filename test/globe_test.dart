// spec-18 commit 5: the globe. Golden-free: projection geometry, tap areas,
// turning and the Hush rule.

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
    test('close-up: your harbor low and centred, the Lantern near the top', () {
      final p = GlobeProjection(size: _size, centerLon: 0, mode: GlobeMode.closeUp);
      final harbor = p.harborAt(0)!;
      expect(harbor.dx, closeTo(_size.width / 2, 0.5));
      expect(harbor.dy, closeTo(_size.height * 0.78, 0.5));
      expect(p.lantern.dy, lessThan(_size.height * 0.2));
      expect(p.project(math.pi / 2, 0).front, isTrue);
    });

    test('a harbor on the far side is not shown; a neighbour is to the right', () {
      final p = GlobeProjection(size: _size, centerLon: 0, mode: GlobeMode.closeUp);
      expect(p.harborAt(4), isNull);
      final next = p.harborAt(1)!;
      expect(next.dx, greaterThan(_size.width / 2));
    });

    test('turning to a harbor brings it to the front', () {
      final p = GlobeProjection(size: _size, centerLon: slotAngle(4), mode: GlobeMode.closeUp);
      expect(p.harborAt(4)!.dx, closeTo(_size.width / 2, 0.5));
      expect(p.harborAt(0), isNull);
    });

    test('whole planet fits in its box', () {
      const box = Size(390, 600);
      final p = GlobeProjection(size: box, centerLon: 0, mode: GlobeMode.whole);
      expect(p.radius * 2, lessThanOrEqualTo(box.width));
      for (var s = 0; s < kHarborSlots; s++) {
        final at = p.harborAt(s);
        if (at != null) {
          expect(Offset.zero & box, isNot(equals(null)));
          expect(at.dx, inInclusiveRange(0, box.width));
          expect(at.dy, inInclusiveRange(0, box.height));
        }
      }
    });

    test('every village tap area is at least 48 x 48', () {
      for (final mode in GlobeMode.values) {
        final p = GlobeProjection(size: const Size(360, 420), centerLon: 0, mode: mode);
        for (var s = 0; s < kHarborSlots; s++) {
          final r = p.villageHit(s);
          if (r == null) continue;
          expect(r.width, greaterThanOrEqualTo(48));
          expect(r.height, greaterThanOrEqualTo(48));
        }
      }
    });
  });

  group('the Hush by reach', () {
    test('land above your reach is hushed, below it is clear, sea never', () {
      // Whisper Woods cell straight above slot 0's harbor.
      final woods = kLanternRow + 80;
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
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: _size.width,
            height: _size.height,
            child: GlobeView(
              mode: GlobeMode.closeUp,
              villages: [for (final s in slots) GlobeVillage(slot: s, name: 'P$s', buildings: const ['WELL'])],
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

  testWidgets('a swipe turns to the next filled harbor only', (tester) async {
    int? turned;
    await tester.pumpWidget(host(focus: 0, slots: [0, 2, 4], onTurn: (s) => turned = s));
    await tester.fling(find.byType(GlobeView), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(turned, 2); // slot 1 is an open bay: skipped
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
