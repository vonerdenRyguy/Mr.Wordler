import 'package:flutter/painting.dart' show Color;

import '../game/word_runs.dart';
import 'magic_word.dart';

// One structure currently built on the board: a magic word's footprint
// plus which structure it is. Purely derived from the current board state
// -- if the word's letters get moved away, the structure disappears next
// recompute. Village view is a rendering of the same grid data, not a
// separate data model; there's no persisted "structures list".
class BoardStructure {
  final MagicWordDef def;
  final Set<int> positions;
  // The footprint in reading order, and which way the word runs.
  final List<int> ordered;
  final bool across;

  BoardStructure({required this.def, required this.positions, List<int>? ordered, this.across = true})
      : ordered = ordered ?? (positions.toList()..sort());

  /// The footprint cell nearest the middle of the word.
  int get middle => ordered[(ordered.length - 1) ~/ 2];
}

/// Board index -> its building's color, for the stripe on Words view
/// tiles that belong to a built magic word.
Map<int, Color> buildingStripes(List<BoardStructure> structures) => {
      for (final structure in structures)
        for (final position in structure.positions) position: structure.def.color,
    };

/// One structure per magic-word run. Every copy of a word is its own run,
/// so two WELLs are two buildings.
List<BoardStructure> computeStructures(List<WordRun> runs) {
  final structures = <BoardStructure>[];
  for (final run in runs) {
    final def = magicWordFor(run.word);
    if (def != null) {
      structures.add(BoardStructure(
        def: def,
        positions: run.positions.toSet(),
        ordered: run.positions,
        across: run.across,
      ));
    }
  }
  return structures;
}
