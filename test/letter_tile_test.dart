import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_board_widget.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/letter_tile.dart';
import 'package:namer_app/game/tile_location.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/village/village_cards.dart';

void main() {
  testWidgets('LetterTile draws a big Lilita One letter', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: SizedBox(width: 48, height: 48, child: LetterTile(letter: 'A'))),
    ));
    final text = tester.widget<Text>(find.text('A'));
    expect(text.style!.fontFamily, 'LilitaOne');
    expect(text.style!.fontSize, greaterThanOrEqualTo(24));
  });

  double tilt(WidgetTester tester) => tester
      .widgetList<Transform>(find.ancestor(of: find.text('Q'), matching: find.byType(Transform)))
      .map((t) => t.transform.storage[1].abs())
      .fold(0.0, (a, b) => a > b ? a : b);

  testWidgets('a loose letter tilts a little, and not with Reduce motion', (tester) async {
    Widget app({required bool reduce}) => MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce), child: child!),
          home: const Center(child: SizedBox(width: 48, height: 48, child: LetterTile(letter: 'Q', loose: true))),
        );
    await tester.pumpWidget(app(reduce: false));
    expect(tilt(tester), greaterThan(0.04)); // sin(3 degrees) is about 0.052
    await tester.pumpWidget(app(reduce: true));
    expect(tilt(tester), 0);
    expect(find.bySemanticsLabel('Letter Q, not in a word yet'), findsOneWidget);
  });

  testWidgets('tapping a loose board letter reports it; a settled one does nothing', (tester) async {
    int? tapped;
    await tester.pumpWidget(ProviderScope(
      overrides: [gridConfigProvider.overrideWithValue(const GridConfig(boardWidth: 3, boardHeight: 1, rackSize: 3))],
      child: MaterialApp(
        home: Scaffold(body: GridBoardView(looseCells: const {1}, onLooseTap: (i) => tapped = i)),
      ),
    ));
    final container = ProviderScope.containerOf(tester.element(find.byType(GridBoardView)));
    container.read(gridGameControllerProvider.notifier).restoreState(
          boardCells: const ['C', 'Q', 'T'],
          rackCells: const [null, null, null],
          pool: const [],
          dealtLetters: const ['C', 'Q', 'T'],
        );
    await tester.pump();
    await tester.tap(find.text('C'));
    expect(tapped, isNull);
    await tester.tap(find.text('Q'));
    expect(tapped, 1);
  });

  testWidgets('the Not a word card names the run that is not a word', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NotAWordCard(run: 'AQ'))));
    expect(find.textContaining("AQ isn't a word yet"), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NotAWordCard())));
    expect(find.textContaining('Not a word yet'), findsOneWidget);
  });

  Future<void> spellCat(WidgetTester tester, {bool reduceMotion = false}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        gridConfigProvider.overrideWithValue(const GridConfig(boardWidth: 3, boardHeight: 1, rackSize: 3)),
        wordCheckProvider.overrideWithValue((w) async => w == 'CAT'),
      ],
      child: MaterialApp(
        builder: (context, child) => reduceMotion
            ? MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!)
            : child!,
        home: const Scaffold(body: GridBoardView()),
      ),
    ));
    final container = ProviderScope.containerOf(tester.element(find.byType(GridBoardView)));
    final controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: const [null, null, null],
      rackCells: const ['C', 'A', 'T'],
      pool: const [],
      dealtLetters: const ['C', 'A', 'T'],
    );
    for (int i = 0; i < 3; i++) {
      controller.moveTile(TileLocation(TileZone.rack, i), TileLocation(TileZone.board, i));
    }
    await tester.pump();
    await tester.pump();
  }

  testWidgets('spelling a real word shows the banner, which then goes away', (tester) async {
    await spellCat(tester);
    expect(find.text('CAT'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('CAT'), findsNothing);
  });

  testWidgets('with reduce motion the banner still shows and no tile is scaled', (tester) async {
    await spellCat(tester, reduceMotion: true);
    expect(find.text('CAT'), findsOneWidget);
    for (int frame = 0; frame < 10; frame++) {
      final transforms = find.descendant(of: find.byType(LetterTile), matching: find.byType(Transform));
      for (final element in transforms.evaluate()) {
        expect((element.widget as Transform).transform.getMaxScaleOnAxis(), closeTo(1.0, 1e-9));
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  });
}
