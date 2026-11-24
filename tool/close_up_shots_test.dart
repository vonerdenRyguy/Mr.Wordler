import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/letterra/close_up.dart';
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_painter.dart';

import '../test/big_test_village.dart';
import '../test/widget_test.dart' show loadAppFonts;

// Pictures and paint times of the close-up test (not in the normal suite).
void main() {
  setUpAll(loadAppFonts);
  testWidgets('close up', (tester) async {
    await tester.runAsync(GlobeArt.load);
    final villages = bigTestVillage();
    // ignore: avoid_print
    print('${villages.first.letters.length} letters, ${villages.first.buildingRuns.length} buildings');
    for (final (name, zoom, row, col) in const [
      ('whole', 1.0, 320.0, 250.0),
      ('z3', 3.0, 350.0, 250.0),
      ('z7', 7.0, 350.0, 250.0),
      ('z9', 9.0, 350.0, 250.0),
      ('z12', 12.0, 350.0, 250.0),
      ('z12shore', 12.0, 366.0, 250.0),
    ]) {
      final s = boardToSphere(row, col);
      const size = Size(411, 891);
      GlobePainter painter(GlobeDetail d) => GlobePainter(
            centerLon: s.lon,
            centerLat: s.lat,
            zoom: zoom,
            villages: villages,
            takenSlots: const {0},
            isHushed: (r, c, _) => hushedByReach(r, c, 2),
            showTags: false,
            closeUp: true,
            detail: d,
            art: GlobeArt.loaded,
          );
      final sw = Stopwatch();
      for (var i = 0; i < 25; i++) {
        if (i == 5) sw.start();
        final rec = ui.PictureRecorder();
        painter(GlobeDetail.coarse).paint(Canvas(rec), size);
        rec.endRecording();
      }
      // ignore: avoid_print
      print('$name ${(sw.elapsedMicroseconds / 20000).toStringAsFixed(2)} ms');
      await tester.runAsync(() async {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec)..scale(2);
        painter(GlobeDetail.fine).paint(canvas, size);
        final image = await rec.endRecording().toImage(822, 1782);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/shots/cu-$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    for (var style = 0; style < 5; style++) {
      plainStyle = style;
      await tester.runAsync(() async {
        final s = boardToSphere(350, 250);
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec)..scale(2);
        GlobePainter(
          centerLon: s.lon,
          centerLat: s.lat,
          zoom: 12,
          villages: villages,
          takenSlots: const {0},
          isHushed: (r, c, _) => hushedByReach(r, c, 2),
          showTags: false,
          closeUp: true,
          art: GlobeArt.loaded,
        ).paint(canvas, const Size(390, 844));
        final bytes = await (await rec.endRecording().toImage(780, 1688)).toByteData(format: ui.ImageByteFormat.png);
        File('build/shots/style$style.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
