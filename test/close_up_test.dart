// spec-22 C: the close-up's buildings and letters.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/letterra/close_up.dart';
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/letterra/planet_data.dart';
import 'package:namer_app/letterra/street.dart';
import 'package:namer_app/players/players.dart';
import 'package:namer_app/village/village_layout.dart' show VillagerSprite;
import 'package:namer_app/village/magic_word.dart';
import 'package:namer_app/villagers/walkers.dart';

import 'big_test_village.dart';

const _phone = Size(411, 891);

GlobeProjection _lookAt(int cell, double zoom) {
  final s = boardToSphere(cell ~/ kPlanetBoard + 0.5, cell % kPlanetBoard + 0.5);
  return GlobeProjection(size: _phone, centerLon: s.lon, centerLat: s.lat, zoom: zoom, closeUp: true);
}

bool _inside(List<Offset> quad, Offset p) => (Path()..addPolygon(quad, true)).contains(p);

// A village of building words and others, crossing at random.
GlobeVillage _randomVillage(int seed) {
  final random = Random(seed);
  final letters = <int, String>{};
  final words = [for (final m in kMagicWords) m.word, 'CAT', 'STREAM', 'ORCHARD', 'PILLOW'];
  for (var n = 0; n < 40; n++) {
    final word = words[random.nextInt(words.length)];
    final step = random.nextBool() ? 1 : kPlanetBoard;
    final start = (325 + random.nextInt(34)) * kPlanetBoard + 230 + random.nextInt(34);
    final cells = [for (var i = 0; i < word.length; i++) start + i * step];
    var ok = !letters.containsKey(start - step) && !letters.containsKey(cells.last + step);
    for (var i = 0; i < cells.length; i++) {
      final there = letters[cells[i]];
      if (there != null && there != word[i]) ok = false;
    }
    if (!ok) continue;
    for (var i = 0; i < cells.length; i++) {
      letters[cells[i]] = word[i];
    }
  }
  return GlobeVillage(slot: 0, name: 'Random $seed', letters: letters, buildingRuns: magicRunsOn(letters));
}

List<GlobeVillage> _villages() => [bigTestVillage().first, for (var i = 0; i < 20; i++) _randomVillage(i)];

void main() {
  test('every building word has its own picture', () {
    final pictures = {for (final m in kMagicWords) GlobePainter.spriteForWord(m.word)};
    expect(pictures, hasLength(kMagicWords.length));
    expect(pictures, contains(GlobeSprite.farm));
  });

  test('a house never stands on a letter or on another house', () {
    for (final v in _villages()) {
      final homes = <int>{};
      expect(v.buildingRuns, isNotEmpty);
      for (final run in v.buildingRuns) {
        final home = homeOf(v, run.cells)!;
        expect(v.letters.containsKey(home.cell), isFalse, reason: '${run.word} in ${v.name}');
        expect(homes.add(home.cell), isTrue);
      }
    }
  });

  test('the same letters always give the same place', () {
    final a = bigTestVillage().first, b = bigTestVillage().first;
    for (final run in a.buildingRuns) {
      expect(homeOf(a, run.cells), homeOf(b, run.cells));
    }
  });

  test('up close, a house is in plain sight and covers no letter', () {
    for (final v in _villages()) {
      for (final zoom in const [7.0, kCloseUpMaxZoom]) {
        for (final run in v.buildingRuns) {
          final proj = _lookAt(homeOf(v, run.cells)!.cell, zoom);
          final house = houseRect(proj, v, run.cells)!;
          for (final cell in v.letters.keys) {
            final top = blockTop(proj, cell);
            if (top == null) continue;
            final reason = '${run.word} in ${v.name} at zoom $zoom, letter ${v.letters[cell]} at $cell';
            expect(_inside(top, house.center), isFalse, reason: reason);
            final mid = (top[0] + top[1] + top[2] + top[3]) / 4;
            expect(house.deflate(1).contains(mid), isFalse, reason: reason);
          }
        }
      }
    }
  });

  test('loose letters reach the planet, turned with the village', () {
    const me = Player(id: 'a', name: 'Me', colorIndex: 0);
    const other = Player(id: 'b', name: 'Other', colorIndex: 1);
    const cell = 340 * kPlanetBoard + 252;
    final data = PlanetData.of(
      const PlanetVillage(player: me, slot: 0, letters: {cell: 'A'}, loose: {cell}),
      const [
        PlanetVillage(player: other, slot: 0, letters: {cell: 'B'}, loose: {cell}),
      ],
    );
    for (final v in data.villages) {
      expect(v.loose, isNotEmpty);
      expect(v.letters.keys.toSet(), v.loose);
    }
    expect(data.villages.first.loose, {cell});
  });

  test("a tap on every letter's middle finds that letter's word, at zoom 7 and 12", () {
    final v = bigTestVillage().first;
    for (final zoom in const [kStreetZoom, kCloseUpMaxZoom]) {
      for (final cell in v.letters.keys) {
        final proj = _lookAt(cell, zoom);
        final top = blockTop(proj, cell)!;
        final hit = streetHit((top[0] + top[1] + top[2] + top[3]) / 4, proj, v);
        switch (hit) {
          case StreetBuilding(:final run):
            expect(v.buildingRuns[run].cells, contains(cell));
          case StreetLetter(cell: final found):
            expect(found, cell);
          default:
            fail('nothing at $cell');
        }
      }
      for (var i = 0; i < v.buildingRuns.length; i++) {
        final cells = v.buildingRuns[i].cells;
        final proj = _lookAt(homeOf(v, cells)!.cell, zoom);
        final hit = streetHit(houseRect(proj, v, cells)!.center, proj, v);
        expect(hit, isA<StreetBuilding>().having((h) => h.run, 'run', i));
      }
    }
  });

  test('a villager is found ahead of the letter they stand on; open sky finds nothing', () {
    final v = bigTestVillage().first;
    final cell = v.letters.keys.first;
    final proj = _lookAt(cell, kCloseUpMaxZoom);
    final at = blockSpot(proj, cell ~/ kPlanetBoard + 0.0, cell % kPlanetBoard + 0.0)!;
    final hit = streetHit(at.at.translate(0, -at.cell * 0.5), proj, v,
        villagers: {'v0': (r: cell ~/ kPlanetBoard + 0.0, c: cell % kPlanetBoard + 0.0)});
    expect(hit, isA<StreetVillager>());
    expect(streetHit(const Offset(200, 5), proj, v), isNull);
  });

  testWidgets('the spot in the middle is kept both ways, at every harbor and near the Lantern', (tester) async {
    for (final cell in [
      for (var slot = 0; slot < kHarborSlots; slot++) harborCell(slot),
      harborCell(0) + 7 * kPlanetBoard + 3,
      harborCell(3) - 20,
      253 * kPlanetBoard + 252,
      250 * kPlanetBoard + 250,
      245 * kPlanetBoard + 251,
    ]) {
      final key = GlobalKey<GlobeViewState>();
      await tester.pumpWidget(MaterialApp(
        home: GlobeView(
          key: key,
          villages: const [],
          takenSlots: const {0},
          focusSlot: 0,
          isHushed: (_, __, ___) => false,
          closeUp: true,
          initialCell: cell,
          initialZoom: kCloseUpMaxZoom,
        ),
      ));
      expect(key.currentState!.centerCell, cell);
    }
  });

  Future<VillagerWalkers> streets(WidgetTester tester, {required bool reduceMotion}) async {
    const cell = 340 * kPlanetBoard + 250;
    final walkers = VillagerWalkers(seed: 3)..sync({'v0': cell}, {for (var i = 0; i < 8; i++) cell + i});
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: StreetVillagers(
          proj: _lookAt(cell, kCloseUpMaxZoom),
          walkers: walkers,
          sprites: const [VillagerSprite(id: 'v0', name: 'Pip')],
        ),
      ),
    ));
    return walkers;
  }

  testWidgets('villagers stroll along the blocks, and stop when the streets are out of view', (tester) async {
    final walkers = await streets(tester, reduceMotion: false);
    var moved = 0;
    walkers.addListener(() => moved++);
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(moved, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    moved = 0;
    await tester.pump(const Duration(seconds: 10));
    expect(moved, 0);
  });

  testWidgets('with Reduce motion villagers stand still', (tester) async {
    final walkers = await streets(tester, reduceMotion: true);
    final at = walkers.positionOf('v0');
    await tester.pump(const Duration(seconds: 8));
    expect(walkers.positionOf('v0'), at);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
