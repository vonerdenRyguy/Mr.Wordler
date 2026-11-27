import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/dictionary/definition_service.dart';
import 'package:namer_app/game/grid_board_widget.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/letterra/close_up.dart';
import 'package:namer_app/letterra/globe_painter.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/portfolio/portfolio_controller.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/village/words_camera.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDefinitions extends DefinitionService {
  @override
  Future<String?> getDefinition(String word) async => 'A test meaning of $word.';
}

const _size = 500;
const _mid = _size ~/ 2;

int _idx(int r, int c) => r * _size + c;

void main() {
  setUp(() {
    // A version-2 village: WELL across the middle, CAT across 3 rows
    // below, joined by an E down... (connection doesn't matter here).
    final board = List<String?>.filled(_size * _size, null);
    'WELL'.split('').asMap().forEach((i, l) => board[_idx(_mid, _mid - 2 + i)] = l);
    'CAT'.split('').asMap().forEach((i, l) => board[_idx(_mid + 3, _mid - 2 + i)] = l);
    SharedPreferences.setMockInitialValues({
      'homeIntroSeen': true,
      'infiniteEstateVillageSave': jsonEncode({
        'boardCells': board,
        'rackCells': List<String>.filled(10, 'E'),
        'pool': List<String>.filled(50, 'E'),
        'dealtLetters': [...'WELLCAT'.split(''), ...List<String>.filled(10, 'E')],
        'lastCashedOutScore': 0,
        'discoveredWords': ['WELL'],
        'saveVersion': 6,
        'planet': {'slot': 0},
      }),
    });
  });

  Future<void> openVillage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wordCheckProvider.overrideWithValue((w) async => {'WELL', 'CAT'}.contains(w)),
        definitionServiceProvider.overrideWithValue(_FakeDefinitions()),
      ],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-my-village')));
    await tester.pumpAndSettle();
  }

  Matrix4 wordsCamera(WidgetTester tester) => tester
      .widget<InteractiveViewer>(
          find.descendant(of: find.byType(GridBoardView), matching: find.byType(InteractiveViewer)))
      .transformationController!
      .value;

  int wordsCenter(WidgetTester tester) {
    final c = centerCellOfFlatView(wordsCamera(tester), tester.getSize(find.byType(GridBoardView)), 44,
        boardWidth: _size, boardHeight: _size);
    return c.r * _size + c.c;
  }

  GlobeViewState globe(WidgetTester tester) => tester.state<GlobeViewState>(find.byType(GlobeView));

  GlobePainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.descendant(of: find.byType(GlobeView), matching: find.byType(CustomPaint)))
      .map((p) => p.painter)
      .whereType<GlobePainter>()
      .first;

  GlobeProjection projection(WidgetTester tester) {
    final p = painter(tester);
    return GlobeProjection(
        size: tester.getSize(find.byType(GlobeView)),
        centerLon: p.centerLon,
        centerLat: p.centerLat,
        zoom: p.zoom,
        closeUp: true);
  }

  Offset middleOf(List<Offset> top) => (top[0] + top[1] + top[2] + top[3]) / 4;

  testWidgets('up close, the Well opens its card, its letters too, and a word its meaning', (tester) async {
    await openVillage(tester);
    expect(find.byTooltip('1 building'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('words-planet')));
    await tester.pumpAndSettle();

    final v = painter(tester).villages.first;
    final run = v.buildingRuns.single;
    Future<void> expectWell(Offset at) async {
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(find.text('Well'), findsWidgets);
      expect(find.text('A test meaning of WELL.'), findsOneWidget);
      expect(find.text('Draw a free letter'), findsOneWidget);
      expect(find.text('Build here'), findsOneWidget);
      expect(painter(tester).highlight, run.cells.toSet());
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    }

    await expectWell(houseRect(projection(tester), v, run.cells)!.center);
    await expectWell(middleOf(blockTop(projection(tester), run.cells[1])!));

    final cat = v.letters.keys.where((c) => !run.cells.contains(c)).toList()..sort();
    await tester.tapAt(middleOf(blockTop(projection(tester), cat[1])!));
    await tester.pumpAndSettle();
    expect(find.text('CAT means'), findsOneWidget);
    expect(find.text('A test meaning of CAT.'), findsOneWidget);
    await tester.tap(find.text('Build here'));
    await tester.pumpAndSettle();
    expect(wordsCenter(tester), cat[1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('far out, the village is one tap: it flies down and stays', (tester) async {
    await openVillage(tester);
    await tester.tap(find.byKey(const ValueKey('words-planet')));
    await tester.pumpAndSettle();
    globe(tester).showWhole(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planet-build')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('globe-village-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planet-build')), findsOneWidget);
    expect(globe(tester).zoom, kCloseUpMaxZoom);
  });

  testWidgets('Planet and Build keep the same square', (tester) async {
    await openVillage(tester);
    final start = wordsCenter(tester);
    await tester.tap(find.byKey(const ValueKey('words-planet')));
    await tester.pumpAndSettle();
    expect(globe(tester).centerCell, start);
    await tester.pump(const Duration(seconds: 3)); // the XP note goes
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planet-build')));
    await tester.pumpAndSettle();
    expect(wordsCenter(tester), start);
  });

  testWidgets('with the planet still and nobody walking, nothing is animating', (tester) async {
    await openVillage(tester);
    await tester.tap(find.byKey(const ValueKey('words-planet')));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    final data = painter(tester).villages;
    await tester.pump(const Duration(seconds: 1));
    expect(identical(painter(tester).villages, data), isTrue);
  });

  testWidgets('a new building pays once, also when its moment is closed by Back, and Words is as it was', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'infiniteEstateVillageSave';
    final save = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    await prefs.setString(key, jsonEncode(save..['discoveredWords'] = <String>[]));
    await openVillage(tester);
    expect(find.text('You built a Well!'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    int coins() => container.read(portfolioProvider).currency;
    final paid = coins();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('You built a Well!'), findsNothing);
    expect(find.byType(GridBoardView), findsOneWidget);
    expect(find.byType(GlobeView), findsNothing);
    expect(coins(), paid);

    await tester.tap(find.byTooltip('Leave village (it saves automatically)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-my-village')));
    await tester.pumpAndSettle();
    expect(find.text('You built a Well!'), findsNothing);
    expect(coins(), paid);
    final again = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    expect(again['discoveredWords'], ['WELL']);
  });
}
