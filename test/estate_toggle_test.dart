import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_board_widget.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/letter_tile.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/letterra/globe_view.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/village/magic_word.dart';
import 'package:namer_app/game/word_runs.dart';
import 'package:namer_app/village/structures.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Home's first-time intro card has been seen.
    SharedPreferences.setMockInitialValues({'homeIntroSeen': true});
  });

  testWidgets('My village opens Words; Planet and Build go between them', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-my-village')));
    await tester.pumpAndSettle();

    expect(find.byType(GridBoardView), findsOneWidget);
    expect(find.byType(GlobeView), findsNothing);

    await tester.tap(find.byKey(const ValueKey('words-planet')));
    await tester.pumpAndSettle();
    expect(find.byType(GridBoardView), findsNothing);
    expect(find.byType(GlobeView), findsOneWidget);
    // No building yet: the helper stands where Build does.
    expect(find.text('Build your first building'), findsOneWidget);

    await tester.tap(find.text('Go to Words'));
    await tester.pumpAndSettle();
    expect(find.byType(GridBoardView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tiles of a built magic word get its stripe, others do not', (tester) async {
    final well = kMagicWords.firstWhere((d) => d.word == 'WELL');
    final stripes = buildingStripes(computeStructures(const [
      WordRun('WELL', [0, 1, 2, 3], true),
      WordRun('AX', [4, 5], true),
    ]));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        gridConfigProvider.overrideWithValue(const GridConfig(boardWidth: 6, boardHeight: 1, rackSize: 1)),
        wordCheckProvider.overrideWithValue((w) async => w == 'WELL'),
      ],
      child: MaterialApp(home: Scaffold(body: GridBoardView(stripes: stripes))),
    ));
    final container = ProviderScope.containerOf(tester.element(find.byType(GridBoardView)));
    container.read(gridGameControllerProvider.notifier).restoreState(
          boardCells: const ['W', 'E', 'L', 'L', 'A', 'X'],
          rackCells: const [null],
          pool: const [],
          dealtLetters: const ['W', 'E', 'L', 'L', 'A', 'X'],
        );
    await tester.pump();

    final tiles = tester.widgetList<LetterTile>(find.byType(LetterTile)).toList();
    expect(tiles.length, 6);
    for (final tile in tiles) {
      if ('WEL'.contains(tile.letter)) {
        expect(tile.stripe, well.color, reason: tile.letter);
      } else {
        expect(tile.stripe, isNull, reason: tile.letter);
      }
    }
  });
}
