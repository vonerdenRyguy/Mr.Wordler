// spec-18b: the planet's painted look.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/planet.dart';

void main() {
  test('nothing stands on the sea, whoever holds a harbor', () {
    for (final members in [0, 1, 3, 8]) {
      final taken = takenSlotsFor(members);
      final decor = globeDecorFor(taken);
      expect(decor, isNotEmpty);
      for (final d in decor) {
        expect(bandAt(d.row, d.col), isNot(Band.deep));
        expect(isBay(d.row, d.col, taken), isFalse);
      }
    }
  });

  test('the Hush thins towards the shore, so there is always somewhere to see', () {
    expect(hushThickness(Band.sunnyShore), 0);
    expect(hushThickness(Band.meadow), lessThan(hushThickness(Band.whisperWoods)));
    expect(hushThickness(Band.whisperWoods), lessThan(hushThickness(Band.ruinHills)));
  });

  testWidgets('the art loads and paints at every zoom', (tester) async {
    await tester.runAsync(GlobeArt.load);
    final art = GlobeArt.loaded!;
    addTearDown(() => GlobeArt.loaded = null);
    final map = art.mapFor(const {0});
    expect(map.width, map.height);
    for (final zoom in [1.0, 2.5, 7.0]) {
      final recorder = ui.PictureRecorder();
      GlobePainter(
        centerLon: 0,
        centerLat: 0.2,
        zoom: zoom,
        villages: const [GlobeVillage(slot: 0, name: 'Me', letters: {364 * 500 + 250: 'A'})],
        takenSlots: const {0},
        isHushed: (r, c, l) => true,
        art: art,
      ).paint(Canvas(recorder), const Size(411, 560));
      recorder.endRecording().dispose();
    }
    expect(tester.takeException(), isNull);
  });
}
