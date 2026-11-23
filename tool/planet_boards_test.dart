// Renders planned Letterra screens with the app's own painter, for the design
// canvas (not part of the normal suite). Prints where things are on screen.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_painter.dart';

void main() {
  const size = Size(390, 844);
  testWidgets('boards', (tester) async {
    await tester.runAsync(GlobeArt.load);
    Future<void> shot(String name,
        {required Set<int> slots, double lon = 0, double lat = 0.34, double zoom = 1, required bool Function(int, int, double) hush, bool empty = false}) async {
      const words = {0: ['WELL', 'BARN', 'HOUSE'], 1: ['MILL', 'FARM'], 7: ['BARN', 'TOWER'], 2: ['FARM']};
      final painter = GlobePainter(
        centerLon: lon, centerLat: lat, zoom: zoom,
        villages: [for (final s in slots) GlobeVillage(slot: s, name: '', buildings: words[s] ?? const ['FARM'])],
        takenSlots: slots, isHushed: hush, showTags: false, art: GlobeArt.loaded,
      );
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(2);
      painter.paint(c, size);
      final pic = rec.endRecording();
      await tester.runAsync(() async {
        final img = await pic.toImage(780, 1688);
        final b = await img.toByteData(format: ui.ImageByteFormat.png);
        File('build/shots/pb-$name.png').writeAsBytesSync(b!.buffer.asUint8List());
      });
      final proj = GlobeProjection(size: size, centerLon: lon, centerLat: lat, zoom: zoom);
      final out = StringBuffer('$name lantern ${proj.lantern}');
      for (final s in [0, 1, 7]) {
        out.write(' h$s ${proj.harborAt(s)}');
      }
      // ignore: avoid_print
      print(out);
      for (final la in [10, 20, 30, 40, 50, 60, 70]) {
        final row = [for (final lo in [-45, -30, -15, 0, 15, 30, 45]) proj.project(la * math.pi / 180, lo * math.pi / 180).p];
        // ignore: avoid_print
        print('  lat $la: ${row.map((p) => '${p.dx.round()},${p.dy.round()}').join(' ')}');
      }
    }

    double lonOf(int r, int c) => math.atan2((c - 250).toDouble(), (r - 250).toDouble());
    double dist(int r, int c) => math.sqrt((r - 250) * (r - 250) + (c - 250) * (c - 250) + 0.0);
    // A path of cleared land climbing from your harbor.
    bool climbed(int r, int c, double _) => !(dist(r, c) > 60 && lonOf(r, c).abs() < 0.34 + 0.06 * math.sin(dist(r, c)));
    await shot('find', slots: {0, 4}, hush: climbed);
    await shot('roads', slots: {0, 1, 7, 4}, hush: (r, c, _) => !(dist(r, c) > 74 && lonOf(r, c).abs() < 1.25));
    await shot('lit', slots: {0, 1, 2, 3, 4, 5, 6, 7}, hush: (r, c, _) => false);
    await shot('bay', slots: {0, 7, 4}, hush: climbed, lon: 0.45);
    await shot('rise', slots: {0, 1, 7, 4}, hush: climbed, lon: 0.45);
  });
}
