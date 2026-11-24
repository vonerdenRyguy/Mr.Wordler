// ignore_for_file: invalid_use_of_visible_for_testing_member
// Pictures for the spec-22 B and C boards (not in the normal suite).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/fog.dart';
import 'package:namer_app/game/word_landing.dart' show wordCheckProvider;
import 'package:namer_app/letterra/globe_art.dart';
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/screens/close_up_test_screen.dart';
import 'package:namer_app/screens/infinite_estate_screen.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/village/magic_word.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/home_test_helpers.dart';
import '../test/widget_test.dart' show loadAppFonts;

const _size = Size(390, 844);
const _all = {0, 1, 2, 3, 4, 5, 6, 7};

void main() {
  setUpAll(loadAppFonts);
  testWidgets('boards', (tester) async {
    await tester.runAsync(() async {
      final root = Platform.environment['FLUTTER_ROOT'];
      final font = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      await (FontLoader('MaterialIcons')..addFont(Future.value(font.readAsBytesSync().buffer.asByteData()))).load();
    });
    await tester.runAsync(GlobeArt.load);
    final villages = closeUpTestVillages();
    Future<void> save(String name, ui.Picture picture) => tester.runAsync(() async {
          final image = await picture.toImage(780, 1688);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('build/shots/l-$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
    Future<void> planet(String name, double zoom, double lat, double lon,
        {Set<int> taken = const {0}, List<int> waiting = const [], int? settled}) async {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..scale(2);
      GlobePainter(
        centerLon: lon,
        centerLat: lat,
        zoom: zoom,
        villages: villages,
        takenSlots: taken,
        isHushed: (r, c, _) => hushedByReach(r, c, 2),
        showTags: false,
        closeUp: true,
        art: GlobeArt.loaded,
      ).paint(canvas, _size);
      final proj = GlobeProjection(size: _size, centerLon: lon, centerLat: lat, zoom: zoom, closeUp: true);
      void put(double latD, double lonR, GlobeSprite s, double cells, [ColorFilter? filter]) {
        final at = proj.project(latD * math.pi / 180, lonR);
        if (!at.front) return;
        final w = proj.pixelsAt(latD * math.pi / 180, lonR, cells * math.pi / 240);
        canvas.drawImageRect(
          GlobeArt.loaded!.sprites,
          s.rect,
          Rect.fromLTWH(at.p.dx - w / 2, at.p.dy - w * 0.82, w, w),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..colorFilter = filter,
        );
      }

      const blank = ColorFilter.mode(Color(0xC0FFFFFF), BlendMode.srcATop);
      for (final slot in waiting) {
        final base = slotAngle(slot);
        final rnd = math.Random(slot + 3);
        for (var la = 15.0; la >= 2; la -= 2.6) {
          for (var k = -5; k <= 5; k++) {
            if ((k.abs() <= 1 && la < 5) || rnd.nextDouble() < 0.18) continue;
            put(la + rnd.nextDouble(), base + (k * 4.1 + rnd.nextDouble() * 2) * math.pi / 180,
                rnd.nextBool() ? GlobeSprite.puff : GlobeSprite.puffWide, 11 + rnd.nextDouble() * 4);
          }
        }
        put(1.0, base - 5 * math.pi / 180, GlobeSprite.flagGold, 13, blank);
        put(-3.2, base, GlobeSprite.port, 15);
      }
      if (settled != null) {
        final base = slotAngle(settled);
        put(7, base - 3 * math.pi / 180, GlobeSprite.houseGreen, 15);
        put(4, base + 4 * math.pi / 180, GlobeSprite.houseGold, 15);
        put(1.0, base - 6 * math.pi / 180, GlobeSprite.flagGreen, 13);
        put(-3.2, base, GlobeSprite.port, 15);
        put(-7, base + 8 * math.pi / 180, GlobeSprite.boatGreen, 14);
      }
      await save(name, rec.endRecording());
    }

    ({double lat, double lon}) at(double r, double c) => boardToSphere(r, c);
    final mid = at(350, 250);
    await planet('home', 1, 0.46, 0);
    await planet('down', 3.2, mid.lat, 0);
    await planet('streets', 12, mid.lat, mid.lon);
    final tower = at(354, 246);
    await planet('new', 12, tower.lat, tower.lon);
    await planet('wait', 1, 0.42, slotAngle(1) * 0.55, taken: _all, waiting: const [1, 2, 7]);
    await planet('wait2', 4, 0.08, slotAngle(1), taken: _all, waiting: const [1]);
    await planet('join', 1, 0.42, slotAngle(1) * 0.55, taken: _all, waiting: const [2, 7], settled: 1);

    // Words, as it is today, with the same village.
    tester.view.physicalSize = _size * 2;
    tester.view.devicePixelRatio = 2;
    final letters = villages.first.letters;
    final board = List<String?>.filled(kPlanetBoard * kPlanetBoard, null);
    letters.forEach((i, l) => board[i] = l);
    final words = [for (final m in kMagicWords) m.word];
    SharedPreferences.setMockInitialValues({
      'reduceMotion': true,
      'infiniteEstateVillageSave': jsonEncode({
        'boardCells': board,
        'rackCells': 'GARDENSIOT'.split(''),
        'pool': List<String>.filled(50, 'E'),
        'dealtLetters': ['E'],
        'lastCashedOutScore': 0,
        'discoveredWords': words,
        'everUsed': letters.keys.toList(),
        'cleared': FogMap.empty().clearAround(letters.keys.toList(), radius: 5).toBase64(),
        'saveVersion': 6,
        'planet': {'slot': 0},
        'tidiedLoose': true,
      }),
    });
    await skipHomeIntro();
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: ProviderScope(
        overrides: [wordCheckProvider.overrideWithValue((w) async => true)],
        child: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(),
          child: const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: InfiniteEstateScreen(focusCell: 352 * kPlanetBoard + 251),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final bytes = await (await b.toImage(pixelRatio: 2)).toByteData(format: ui.ImageByteFormat.png);
      File('build/shots/l-words.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
