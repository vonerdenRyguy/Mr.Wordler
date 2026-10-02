import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_game_controller.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/tile_location.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/game/word_runs.dart';

void main() {
  const config = GridConfig(boardWidth: 5, boardHeight: 5, rackSize: 5);
  const realWords = {'CAT', 'AT', 'TA'};

  late ProviderContainer container;
  late GridGameController controller;

  void setUpWith(WordCheck check, {List<String?> rack = const ['C', 'A', 'T', 'X', null]}) {
    container = ProviderContainer(overrides: [
      gridConfigProvider.overrideWithValue(config),
      wordCheckProvider.overrideWithValue(check),
    ]);
    addTearDown(container.dispose);
    container.listen(tileLandingProvider, (_, __) {});
    controller = container.read(gridGameControllerProvider.notifier);
    controller.restoreState(
      boardCells: List<String?>.filled(25, null),
      rackCells: rack,
      pool: const ['E', 'E'],
      dealtLetters: rack.whereType<String>().toList(),
    );
  }

  TileLanding? landing() => container.read(tileLandingProvider);
  void place(int rackIndex, int boardIndex) =>
      controller.moveTile(TileLocation(TileZone.rack, rackIndex), TileLocation(TileZone.board, boardIndex));

  test('placing one tile emits a landing right away, with no words yet', () {
    setUpWith((w) async => realWords.contains(w));
    place(0, 12);
    expect(landing()!.placedIndex, 12);
    expect(landing()!.words, isEmpty);
  });

  test('placing C, A, T across emits CAT once the check finishes', () async {
    setUpWith((w) async => realWords.contains(w));
    place(0, 0);
    place(1, 1);
    place(2, 2);
    await pumpEventQueue();
    expect(landing()!.placedIndex, 2);
    expect(landing()!.words, [const WordRun('CAT', [0, 1, 2], true)]);
  });

  test('an invalid run (CX) emits no words', () async {
    setUpWith((w) async => realWords.contains(w));
    place(0, 0);
    place(3, 1);
    await pumpEventQueue();
    expect(landing()!.words, isEmpty);
  });

  test('a rack-to-rack move emits nothing', () async {
    setUpWith((w) async => realWords.contains(w));
    controller.moveTile(const TileLocation(TileZone.rack, 0), const TileLocation(TileZone.rack, 4));
    await pumpEventQueue();
    expect(landing(), isNull);
  });

  test('restoring a board with several letters emits nothing', () async {
    setUpWith((w) async => realWords.contains(w));
    controller.restoreState(
      boardCells: ['C', 'A', 'T', ...List<String?>.filled(22, null)],
      rackCells: const ['X', null, null, null, null],
      pool: const [],
      dealtLetters: const ['C', 'A', 'T', 'X'],
    );
    await pumpEventQueue();
    expect(landing(), isNull);
  });

  test('stale guard: picking the tile back up before the check finishes emits no words', () async {
    final gate = Completer<void>();
    setUpWith((w) async {
      await gate.future;
      return realWords.contains(w);
    });
    place(0, 0);
    place(1, 1);
    place(2, 2); // finishes CAT, check still waiting
    controller.moveTile(const TileLocation(TileZone.board, 2), const TileLocation(TileZone.rack, 2));
    gate.complete();
    await pumpEventQueue();
    expect(landing()!.words, isEmpty);
  });

  test('a board-to-board move that completes a word emits it', () async {
    setUpWith((w) async => realWords.contains(w));
    place(0, 0);
    place(1, 1);
    place(2, 12);
    await pumpEventQueue();
    controller.moveTile(const TileLocation(TileZone.board, 12), const TileLocation(TileZone.board, 2));
    await pumpEventQueue();
    expect(landing()!.placedIndex, 2);
    expect(landing()!.words.map((w) => w.word), ['CAT']);
  });

  test('fxFor marks the placed tile to settle and orders popping tiles across words', () {
    const l = TileLanding(3, 1, [
      WordRun('CAT', [0, 1, 2], true),
      WordRun('AT', [1, 6], false),
    ]);
    expect(fxFor(l, 1), (seq: 3, settle: true, popOrder: 1));
    expect(fxFor(l, 0), (seq: 3, settle: false, popOrder: 0));
    expect(fxFor(l, 6), (seq: 3, settle: false, popOrder: 3)); // shared tile 1 counted once
    expect(fxFor(l, 9), isNull);
    expect(fxFor(null, 0), isNull);
  });
}
