// Renders the globe to PNGs for eyeballing (not part of the normal suite).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/letterra/planet.dart';

void main() {
  int c(int r, int col) => r * kPlanetBoard + col;
  final letters = <int, String>{
    for (var i = 0; i < 4; i++) c(364, 248 + i): 'WELL'[i],
    for (var i = 0; i < 4; i++) c(365 + i, 250): 'BARN'[i],
    for (var i = 0; i < 6; i++) c(360 + i, 255): 'BRIDGE'[i],
    for (var i = 0; i < 4; i++) c(358, 252 + i): 'FARM'[i],
  };
  final runs = magicRunsOn(letters);

  Future<void> shot(WidgetTester tester, String name, {int zoomIns = 0, int zoomOuts = 0, double drag = 0}) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(411, 760);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: GlobeView(
            villages: [
              GlobeVillage(slot: 0, name: 'Me', buildings: const ['WELL', 'BARN'], letters: letters, buildingRuns: runs),
              const GlobeVillage(slot: 4, name: 'Nana', buildings: ['FARM']),
              const GlobeVillage(slot: 2, name: 'Sam', buildings: ['MILL']),
            ],
            takenSlots: const {0, 2, 4},
            focusSlot: 0,
            isHushed: (r, col, lon) => !letters.keys.any((i) {
              final a = i ~/ kPlanetBoard - r, b = i % kPlanetBoard - col;
              return a * a + b * b < 81;
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    for (var i = 0; i < zoomIns; i++) {
      await tester.tap(find.byKey(const ValueKey('globe-zoom-in')));
      await tester.pumpAndSettle();
    }
    for (var i = 0; i < zoomOuts; i++) {
      await tester.tap(find.byKey(const ValueKey('globe-zoom-out')));
      await tester.pumpAndSettle();
    }
    if (drag != 0) {
      await tester.drag(find.byType(GlobeView), Offset(drag, 0));
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('C:/Users/Ryan the Avatar/Desktop/MrWordlerScreenshots/2026-11-23_spec18b/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('shots', (tester) async {
    await tester.runAsync(() async {
      await GlobeArt.load();
      final f = FontLoader('LilitaOne')..addFont(rootBundle.load('assets/fonts/LilitaOne-Regular.ttf'));
      await f.load();
      final a = FontLoader('AtkinsonHyperlegible')..addFont(rootBundle.load('assets/fonts/AtkinsonHyperlegible-Bold.ttf'));
      await a.load();
    });
    await shot(tester, 'g1-default');
    await shot(tester, 'g2-whole', zoomOuts: 2);
    await shot(tester, 'g3-zoom1', zoomIns: 1);
    await shot(tester, 'g4-zoom2', zoomIns: 2);
    await shot(tester, 'g5-zoom-max', zoomIns: 4);
    await shot(tester, 'g6-spun', drag: -300);
  });
}
