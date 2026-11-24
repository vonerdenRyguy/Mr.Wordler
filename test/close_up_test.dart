// spec-22 C: the close-up's buildings and letters.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/letterra/close_up.dart';
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/letterra/planet_data.dart';
import 'package:namer_app/players/players.dart';
import 'package:namer_app/village/magic_word.dart';

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
}
