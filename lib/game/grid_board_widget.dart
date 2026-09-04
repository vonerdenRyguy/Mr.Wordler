import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dictionary/definition_service.dart';
import 'grid_providers.dart';
import 'tile_location.dart';

// Long-press a board tile that's part of a currently valid word to see a
// short definition. Fails silently (no dialog at all) if the word isn't
// valid right now, or no definition is available/cached and the device
// is offline -- this must never interrupt gameplay with an error.
Future<void> _showDefinitionIfAny(BuildContext context, WidgetRef ref, int boardIndex) async {
  final controller = ref.read(gridGameControllerProvider.notifier);
  final word = await controller.validWordAtBoardIndex(boardIndex);
  if (word == null) return;

  final definition = await ref.read(definitionServiceProvider).getDefinition(word);
  if (definition == null) return;
  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.orangeAccent,
      title: Text(word),
      content: Text(definition),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}

// One board cell or rack slot: a drag source/target rendering the letter
// (if any) at `location`. Font size is derived from the tile's own
// rendered size (via LayoutBuilder) rather than a fixed pixel value, so
// text stays legible whether this is a 10x10 board on a phone or a 25x25
// board on a tablet.
class GridTileWidget extends ConsumerWidget {
  const GridTileWidget({super.key, required this.location, required this.isBoardStyle});

  final TileLocation location;
  final bool isBoardStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final letter = ref.watch(gridGameControllerProvider.select(
      (s) => (location.zone == TileZone.board ? s.boardCells : s.rackCells)[location.index],
    ));
    final controller = ref.read(gridGameControllerProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double fontSize = (constraints.maxWidth * 0.5).clamp(10.0, 28.0);
        return DragTarget<TileLocation>(
          builder: (context, candidateData, rejectedData) {
            return Container(
              padding: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: candidateData.isNotEmpty
                    ? Colors.blue[100]
                    : (isBoardStyle ? Colors.orangeAccent : Colors.deepPurple),
                border: Border.all(
                  color: isBoardStyle ? Colors.black : Colors.grey,
                  width: 1.5,
                ),
                borderRadius: isBoardStyle ? BorderRadius.circular(0.0) : BorderRadius.circular(8.0),
              ),
              child: Center(
                child: letter != null
                    ? Draggable<TileLocation>(
                        data: location,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.all(10.0),
                            decoration: const BoxDecoration(
                              color: Colors.deepPurple,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              letter,
                              style: TextStyle(
                                fontFamily: "Open Sans",
                                fontWeight: FontWeight.w900,
                                fontSize: fontSize,
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Container(
                          padding: const EdgeInsets.all(3.0),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                        ),
                        child: GestureDetector(
                          // Only board tiles can be part of a placed word;
                          // rack tiles have nothing to define yet.
                          onLongPress: location.zone == TileZone.board
                              ? () => _showDefinitionIfAny(context, ref, location.index)
                              : null,
                          child: Center(
                            child: Text(
                              letter,
                              style: TextStyle(
                                fontFamily: "Open Sans",
                                fontWeight: FontWeight.w900,
                                fontSize: fontSize,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          },
          onWillAcceptWithDetails: (details) {
            final currentLetter = (location.zone == TileZone.board
                ? ref.read(gridGameControllerProvider).boardCells
                : ref.read(gridGameControllerProvider).rackCells)[location.index];
            return currentLetter == null;
          },
          onAcceptWithDetails: (details) {
            controller.moveTile(details.data, location);
          },
        );
      },
    );
  }
}

// Renders the board as a `boardWidth`-column square grid, pannable/
// zoomable via InteractiveViewer (so a larger-than-phone board, like
// Infinite Estate's, still fits and stays usable on any screen size).
class GridBoardView extends ConsumerWidget {
  const GridBoardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gridGameControllerProvider.select((s) => s.config));
    return InteractiveViewer(
      boundaryMargin: EdgeInsets.zero,
      minScale: 0.2,
      maxScale: 2.5,
      child: Center(
        child: AspectRatio(
          aspectRatio: config.boardWidth / config.boardHeight,
          child: GridView.count(
            crossAxisCount: config.boardWidth,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(config.boardCellCount, (index) {
              return Padding(
                padding: EdgeInsets.zero,
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: GridTileWidget(
                    location: TileLocation(TileZone.board, index),
                    isBoardStyle: true,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// Renders the player's rack.
class GridRackView extends ConsumerWidget {
  const GridRackView({super.key, this.crossAxisCount = 7});

  final int crossAxisCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rackSize = ref.watch(gridGameControllerProvider.select((s) => s.config.rackSize));
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2.0)),
      child: Center(
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.7,
          shrinkWrap: true,
          children: List.generate(rackSize, (index) {
            return Padding(
              padding: const EdgeInsets.all(4.0),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: GridTileWidget(
                  location: TileLocation(TileZone.rack, index),
                  isBoardStyle: false,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
