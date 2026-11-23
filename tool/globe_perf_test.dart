import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/planet.dart';

void main() {
  test('paint time', () {
    for (final detail in GlobeDetail.values) {
      for (final zoom in [1.0, 2.5, 5.0, 7.0]) {
        final painter = GlobePainter(
          centerLon: 0,
          centerLat: 0.2,
          zoom: zoom,
          villages: const [GlobeVillage(slot: 0, name: 'Me')],
          takenSlots: const {0},
          isHushed: (r, c, l) => bandAt(r, c).index > 4,
          detail: detail,
        );
        for (var i = 0; i < 3; i++) {
          final rec = ui.PictureRecorder();
          painter.paint(Canvas(rec), const Size(411, 560));
          rec.endRecording();
        }
        final sw = Stopwatch()..start();
        const n = 20;
        for (var i = 0; i < n; i++) {
          final rec = ui.PictureRecorder();
          painter.paint(Canvas(rec), const Size(411, 560));
          rec.endRecording();
        }
        // ignore: avoid_print
        print('$detail zoom $zoom: ${(sw.elapsedMicroseconds / n / 1000).toStringAsFixed(2)} ms/frame');
      }
    }
  });
}
