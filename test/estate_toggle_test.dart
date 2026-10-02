import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_board_widget.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/letter_tile.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/village/magic_word.dart';
import 'package:namer_app/village/village_board_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the Words side starts selected, and tapping Village moves it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(ProviderScope(
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visit your village'));
    await tester.pumpAndSettle();

    expect(tester.getSemantics(find.bySemanticsLabel('Words view')), containsSemantics(isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Village view')), containsSemantics(isSelected: false));

    await tester.tap(find.bySemanticsLabel('Village view'));
    await tester.pumpAndSettle();

    expect(tester.getSemantics(find.bySemanticsLabel('Words view')), containsSemantics(isSelected: false));
    expect(tester.getSemantics(find.bySemanticsLabel('Village view')), containsSemantics(isSelected: true));
    semantics.dispose();
  });

  testWidgets('tiles of a built magic word get its stripe, others do not', (tester) async {
    final well = kMagicWords.firstWhere((d) => d.word == 'WELL');
    final stripes = buildingStripes(computeStructures({
      'WELL': {0, 1, 2, 3},
      'AX': {4, 5},
    }));
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
