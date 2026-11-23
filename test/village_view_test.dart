import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/dictionary/definition_service.dart';
import 'package:namer_app/game/grid_board_widget.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/village/iso_math.dart';
import 'package:namer_app/village/iso_village_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class _FakeDefinitions extends DefinitionService {
  @override
  Future<String?> getDefinition(String word) async => 'A test meaning of $word.';
}

const _size = 500;
const _mid = _size ~/ 2;
const _grid = IsoGrid(boardWidth: _size, boardHeight: _size);

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
    await tester.tap(find.byKey(const ValueKey('globe-village-0')));
    await tester.pumpAndSettle();
  }

  Matrix4 controllerOf(WidgetTester tester, Type view) => tester
      .widget<InteractiveViewer>(find.descendant(of: find.byType(view), matching: find.byType(InteractiveViewer)))
      .transformationController!
      .value;

  // Content point in Village view -> where to tap on screen.
  Offset onScreen(WidgetTester tester, Offset content) {
    final m = controllerOf(tester, IsoVillageView);
    final v = m.transform3(Vector3(content.dx, content.dy, 0));
    return tester.getTopLeft(find.byType(IsoVillageView)) + Offset(v.x, v.y);
  }

  testWidgets('tapping the Well opens its card; tapping a path opens the word card', (tester) async {
    final semantics = tester.ensureSemantics();
    await openVillage(tester);
    await tester.tap(find.bySemanticsLabel('Village view'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsWidgets); // "1 building" chip

    // The well's sprite stands on its word's middle letter.
    final wellTop = _grid.ground(_mid, _mid - 1) - const Offset(0, isoBlockHeight + 30);
    await tester.tapAt(onScreen(tester, wellTop));
    await tester.pumpAndSettle();
    expect(find.text('Well'), findsWidgets);
    expect(find.text('A test meaning of WELL.'), findsOneWidget);
    expect(find.text('Draw a free letter'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tapAt(onScreen(tester, _grid.ground(_mid + 3, _mid - 1)));
    await tester.pumpAndSettle();
    expect(find.text('CAT means'), findsOneWidget);
    expect(find.text('A test meaning of CAT.'), findsOneWidget);
    expect(find.text('A path in your village. Only magic words become buildings.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('switching Words to Village and back keeps the same center cell', (tester) async {
    await openVillage(tester);
    final wordsSize = tester.getSize(find.byType(GridBoardView));
    final start = centerCellOfFlatView(controllerOf(tester, GridBoardView), wordsSize, 44,
        boardWidth: _size, boardHeight: _size);

    await tester.tap(find.bySemanticsLabel('Village view'));
    await tester.pumpAndSettle();
    final villageSize = tester.getSize(find.byType(IsoVillageView));
    expect(centerCellOfIsoView(controllerOf(tester, IsoVillageView), villageSize, _grid), start);

    await tester.tap(find.bySemanticsLabel('Words view'));
    await tester.pumpAndSettle();
    final back = centerCellOfFlatView(controllerOf(tester, GridBoardView), tester.getSize(find.byType(GridBoardView)), 44,
        boardWidth: _size, boardHeight: _size);
    expect(back, start);
  });
}
