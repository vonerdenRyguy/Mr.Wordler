import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/grid_providers.dart';
import 'magic_word.dart';

// One structure currently built on the board: a magic word's footprint
// (every tile position its letters occupy) plus which structure it is.
// Purely derived from the current board state -- if the word's letters
// get moved away, the structure disappears next recompute. This matches
// the spec's "Village view is a rendering switch on the same grid data,
// not a separate data model" -- there's no persisted "structures list".
class BoardStructure {
  final MagicWordDef def;
  final Set<int> positions;

  const BoardStructure({required this.def, required this.positions});
}

List<BoardStructure> computeStructures(Map<String, Set<int>> wordPositions) {
  final structures = <BoardStructure>[];
  for (final entry in wordPositions.entries) {
    final def = magicWordFor(entry.key);
    if (def != null) {
      structures.add(BoardStructure(def: def, positions: entry.value));
    }
  }
  return structures;
}

const _plainLandColor = Color(0xFFC8E6C9);
const _plotBorderColor = Color(0xFF33691E);

// Renders the same grid positions as GridBoardView, but as the village
// map: a magic word's footprint shows its structure's color/icon: every
// other tile -- whether empty or holding an ordinary (non-magic) letter --
// shows as plain land, not its letter. Read-only (no drag/drop); Words
// view is where placement actually happens.
class VillageBoardView extends ConsumerWidget {
  const VillageBoardView({
    super.key,
    required this.structures,
    this.minScale = 0.06,
    this.maxScale = 3.0,
    this.boundaryMargin = const EdgeInsets.all(600),
    this.landmarkIndices = const {},
  });

  final List<BoardStructure> structures;
  final double minScale;
  final double maxScale;
  final EdgeInsets boundaryMargin;
  final Set<int> landmarkIndices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gridGameControllerProvider.select((s) => s.config));

    final structureByIndex = <int, MagicWordDef>{};
    final anchorIndices = <int>{};
    for (final structure in structures) {
      for (final index in structure.positions) {
        structureByIndex[index] = structure.def;
      }
      // Icon goes on the middle tile of the word's footprint, not every
      // tile, so a 6-letter word reads as "one building" not six icons.
      final sorted = structure.positions.toList()..sort();
      if (sorted.isNotEmpty) anchorIndices.add(sorted[sorted.length ~/ 2]);
    }

    return InteractiveViewer(
      boundaryMargin: boundaryMargin,
      minScale: minScale,
      maxScale: maxScale,
      child: Center(
        child: AspectRatio(
          aspectRatio: config.boardWidth / config.boardHeight,
          child: GridView.count(
            crossAxisCount: config.boardWidth,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(config.boardCellCount, (index) {
              final def = structureByIndex[index];
              final isUnclaimedLandmark = def == null && landmarkIndices.contains(index);
              return Container(
                decoration: BoxDecoration(
                  color: def?.color ?? (isUnclaimedLandmark ? Colors.amber.shade200 : _plainLandColor),
                  border: Border.all(
                    color: isUnclaimedLandmark ? Colors.amber.shade800 : _plotBorderColor,
                    width: isUnclaimedLandmark ? 1.2 : 0.4,
                  ),
                  boxShadow: isUnclaimedLandmark
                      ? [BoxShadow(color: Colors.amber.withOpacity(0.7), blurRadius: 5, spreadRadius: 1)]
                      : null,
                ),
                child: (def != null && anchorIndices.contains(index))
                    ? LayoutBuilder(
                        builder: (context, constraints) => Icon(
                          def.icon,
                          color: Colors.white,
                          size: (constraints.maxWidth * 0.55).clamp(8.0, 24.0),
                        ),
                      )
                    : isUnclaimedLandmark
                        ? LayoutBuilder(
                            builder: (context, constraints) => Icon(
                              Icons.star,
                              color: Colors.amber.shade900,
                              size: (constraints.maxWidth * 0.5).clamp(8.0, 20.0),
                            ),
                          )
                        : null,
              );
            }),
          ),
        ),
      ),
    );
  }
}
