// spec-18b: Home's planet turns by itself and swipes pass it; planet mode
// spins, dives and comes back; other players get their own harbor.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/fog.dart';
import 'package:namer_app/game/grid_board_widget.dart';
import 'package:namer_app/game/word_landing.dart' show wordCheckProvider;
import 'package:namer_app/letterra/close_up.dart';
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/letterra/planet.dart';
import 'package:namer_app/letterra/planet_data.dart';
import 'package:namer_app/letterra/street.dart' show kStreetZoom;
import 'package:namer_app/main.dart';
import 'package:namer_app/players/players.dart';
import 'package:namer_app/screens/home_screen.dart';
import 'package:namer_app/screens/infinite_estate_screen.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart';
import 'widget_test.dart' show loadAppFonts;

const _me = Player(id: kFirstPlayerId, name: 'Me', colorIndex: 0);
const _sam = Player(id: 'p2', name: 'Sam', colorIndex: 1);

int _c(int r, int c) => r * kPlanetBoard + c;

void main() {
  setUpAll(loadAppFonts);

  group('HomeTurn', () {
    test('alone: rests on you, then one full turn back to you', () {
      final t = HomeTurn(2, [2]);
      expect(t.lonAt(0), closeTo(slotAngle(2), 1e-9));
      expect(t.lonAt(HomeTurn.restSeconds), closeTo(slotAngle(2), 1e-9));
      expect(lonDelta(t.lonAt(HomeTurn.restSeconds + 20), slotAngle(6)).abs(), lessThan(1e-9));
      expect(lonDelta(t.lonAt(t.totalSeconds), slotAngle(2)).abs(), lessThan(1e-6));
    });

    test('with others: rests on each in turn, yours first, and ends at yours', () {
      final t = HomeTurn(0, [0, 4, 2]);
      final rests = <int>{};
      for (var s = 0.0; s < t.totalSeconds; s += 0.25) {
        final a = t.lonAt(s), b = t.lonAt(s + 0.25);
        if (a == b) rests.add((a / (math.pi / 4)).round() % kHarborSlots);
      }
      expect(rests.toList(), [0, 2, 4]);
      expect(lonDelta(t.lonAt(t.totalSeconds), 0).abs(), lessThan(1e-6));
    });
  });

  group('PlanetData', () {
    test('another player on the same harbor is shown across the planet, letters intact', () {
      final letters = {for (var i = 0; i < 4; i++) _c(366, 248 + i): 'WELL'[i]};
      final fog = FogMap.empty().clearAround([_c(366, 250)]);
      final d = PlanetData.of(
        PlanetVillage(player: _me, slot: 0, letters: letters, fog: FogMap.empty()),
        [PlanetVillage(player: _sam, slot: 0, letters: letters, runs: magicRunsOn(letters), fog: fog)],
      );
      expect(d.players[0], _me);
      expect(d.players[4], _sam);
      final sam = d.villages[1];
      expect(sam.letters.length, 4);
      expect([for (final c in sam.buildingRuns.single.cells) sam.letters[c]].join(), 'WELL');
      // Sam's cleared land is on Sam's side only.
      expect(d.isHushed(366, 250, 0), isTrue);
      expect(d.isHushed(134, 250, 0), isFalse);
    });

    test('a cell turned all the way round is itself', () {
      for (final cell in [_c(366, 248), _c(250, 250), _c(300, 180)]) {
        expect(turnedCell(turnedCell(cell, 1)!, 3), cell);
        expect(turnedCell(turnedCell(cell, 2)!, 2), cell);
      }
      // Harbor to harbor.
      expect(turnedCell(harborCell(0), 1), harborCell(2));
      expect(turnedCell(harborCell(0), 2), harborCell(4));
    });

    test('a phone full of players all get a harbor', () {
      final d = PlanetData.of(const PlanetVillage(player: _me, slot: 0), [
        for (var i = 2; i <= 6; i++)
          PlanetVillage(player: Player(id: 'p$i', name: 'P$i', colorIndex: i % 6), slot: 0),
      ]);
      expect(d.takenSlots, {0, 4, 2, 6, 1, 5});
    });
  });

  Widget app({bool turns = false}) => ProviderScope(
        overrides: [
          homePlanetTurnsProvider.overrideWithValue(turns),
          wordCheckProvider.overrideWithValue((w) async => w == 'WELL'),
        ],
        child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
      );

  Future<void> start(WidgetTester tester, {Map<String, Object> prefs = const {}, bool turns = false}) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues(prefs);
    await skipHomeIntro();
    await tester.pumpWidget(app(turns: turns));
    if (turns) {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    } else {
      await tester.pumpAndSettle();
    }
  }

  final globe = find.byType(GlobeView);
  double lonOf(WidgetTester tester) => (tester
          .widgetList<CustomPaint>(find.descendant(of: globe, matching: find.byType(CustomPaint)))
          .map((p) => p.painter)
          .whereType<GlobePainter>()
          .first)
      .centerLon;

  testWidgets('a swipe over the planet changes pages; there are no zoom buttons on Home', (tester) async {
    await start(tester);
    expect(find.byKey(const ValueKey('globe-zoom-in')), findsNothing);
    await tester.fling(globe, const Offset(-250, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Play with your family'), findsOneWidget);
  });

  testWidgets("Home's planet rests, then turns", (tester) async {
    await start(tester, turns: true);
    final before = lonOf(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(lonOf(tester), before);
    await tester.pump(const Duration(seconds: 12));
    expect(lonOf(tester), isNot(before));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Reduce motion keeps it still: nothing is animating', (tester) async {
    await start(tester, prefs: {'reduceMotion': true}, turns: true);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(lonOf(tester), 0);
  });

  testWidgets('tap the planet, spin, find, dive to the streets and stay, Build, Planet, back Home', (tester) async {
    await start(tester);
    await tester.tap(globe);
    await tester.pumpAndSettle();
    expect(find.byType(InfiniteEstateScreen), findsOneWidget);
    expect(find.text('Letterra'), findsOneWidget);
    expect(find.text('Daily puzzle'), findsNothing);

    await tester.timedDrag(globe, const Offset(-250, 0), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(lonOf(tester), isNot(0));
    await tester.tap(find.text('My village').last);
    await tester.pumpAndSettle();
    expect(lonDelta(lonOf(tester), 0).abs(), lessThan(1e-6));

    await tester.tap(find.byKey(const ValueKey('globe-village-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('planet-build')), findsNothing); // still flying
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20));
    expect(tester.state<GlobeViewState>(globe).zoom, kCloseUpMaxZoom);
    expect(find.byType(GridBoardView), findsNothing);

    // A new village has no building: its helper leads to Words.
    await tester.tap(find.text('Go to Words'));
    await tester.pumpAndSettle();
    expect(find.byType(GridBoardView), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('words-planet')));
    await tester.pumpAndSettle();
    expect(tester.state<GlobeViewState>(globe).zoom, kCloseUpMaxZoom);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-my-village')), findsOneWidget);
  });

  testWidgets("with two players, the other's village opens to look at", (tester) async {
    final board = List<String?>.filled(kPlanetBoard * kPlanetBoard, null);
    for (var i = 0; i < 4; i++) {
      board[_c(366, 248 + i)] = 'WELL'[i];
    }
    await start(tester, prefs: {
      'reduceMotion': true,
      'playersData': jsonEncode({
        'players': [_me.toJson(), _sam.toJson()],
        'currentId': kFirstPlayerId,
        'nextNumber': 3,
      }),
      'p2_infiniteEstateVillageSave': jsonEncode({
        'boardCells': board,
        'rackCells': List<String>.filled(10, 'E'),
        'pool': List<String>.filled(50, 'E'),
        'dealtLetters': [...'WELL'.split(''), ...List<String>.filled(10, 'E')],
        'lastCashedOutScore': 0,
        'discoveredWords': <String>[],
        'saveVersion': 6,
        'planetSlot': 0,
        'tidiedLoose': true,
      }),
    });
    // Who's playing?
    if (find.text('Me').evaluate().isNotEmpty && globe.evaluate().isEmpty) {
      await tester.tap(find.text('Me').first);
      await tester.pumpAndSettle();
    }
    await tester.tap(globe);
    await tester.pumpAndSettle();
    tester.state<GlobeViewState>(globe).showWhole(4);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('globe-village-4')));
    await tester.pumpAndSettle();
    expect(find.text("Sam's village"), findsOneWidget);
    // Sam's streets, close up, to look at only (spec-22 C).
    for (var i = 0; i < 50 && globe.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    }
    final visit = find.byType(GlobeView).last;
    expect(tester.widget<GlobeView>(visit).closeUp, isTrue);
    expect(tester.state<GlobeViewState>(visit).zoom, kStreetZoom);
    expect(find.byKey(const ValueKey('planet-build')), findsNothing);
    final paint = tester
        .widgetList<CustomPaint>(find.descendant(of: visit, matching: find.byType(CustomPaint)))
        .map((p) => p.painter)
        .whereType<GlobePainter>()
        .first;
    final proj = GlobeProjection(
        size: tester.getSize(visit), centerLon: paint.centerLon, centerLat: paint.centerLat, zoom: paint.zoom, closeUp: true);
    final top = blockTop(proj, paint.villages.first.buildingRuns.first.cells[1])!;
    await tester.tapAt((top[0] + top[1] + top[2] + top[3]) / 4);
    await tester.pumpAndSettle();
    expect(find.text('Well'), findsWidgets);
    expect(find.text('Build here'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back').last);
    await tester.pumpAndSettle();
    expect(find.text("Sam's village"), findsNothing);
    final saved = jsonDecode((await SharedPreferences.getInstance()).getString('p2_infiniteEstateVillageSave')!);
    expect(saved['boardCells'], board);
  });
}
