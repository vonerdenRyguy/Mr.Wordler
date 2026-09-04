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

// Board/rack color theme. Defaults match the look every mode has always
// had; a mode can pass its own (e.g. Infinite Estate's land/estate
// palette) without affecting the others, since they all share this widget.
class GridTheme {
  final Color boardColor;
  final Color rackColor;
  final Color boardBorderColor;

  const GridTheme({
    this.boardColor = Colors.orangeAccent,
    this.rackColor = Colors.deepPurple,
    this.boardBorderColor = Colors.black,
  });

  static const classic = GridTheme();
}

// One board cell or rack slot: a drag source/target rendering the letter
// (if any) at `location`. Font size is derived from the tile's own
// rendered size (via LayoutBuilder) rather than a fixed pixel value, so
// text stays legible whether this is a 10x10 board on a phone or a 25x25
// board on a tablet.
class GridTileWidget extends ConsumerWidget {
  const GridTileWidget({
    super.key,
    required this.location,
    required this.isBoardStyle,
    this.theme = GridTheme.classic,
    this.isLandmark = false,
    this.isPinned = false,
    this.onTogglePin,
    this.preferBalancedRefill = false,
  });

  final TileLocation location;
  final bool isBoardStyle;
  final GridTheme theme;
  // Marks this as a landmark spot (Infinite Estate/Village only -- every
  // other mode leaves this false). Only shows the glow/star while the
  // tile is still empty; once a letter lands here it renders normally,
  // and the landmark-reached event is handled by the caller, not here.
  final bool isLandmark;
  // Rack "pin" (Infinite Estate/Village only): a UI-only marker the
  // player toggles via long-press to remind themselves they're saving
  // this letter for something -- it doesn't affect gameplay at all.
  // onTogglePin null (the default, every other mode) disables the
  // gesture entirely rather than just no-op'ing it.
  final bool isPinned;
  final ValueChanged<int>? onTogglePin;
  // Farm structure ability (Infinite Estate/Village only): see
  // GridGameController.moveTile's preferBalancedRefill doc.
  final bool preferBalancedRefill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final letter = ref.watch(gridGameControllerProvider.select(
      (s) => (location.zone == TileZone.board ? s.boardCells : s.rackCells)[location.index],
    ));
    final controller = ref.read(gridGameControllerProvider.notifier);
    final showLandmarkGlow = isLandmark && letter == null;
    final showPin = location.zone == TileZone.rack && isPinned && letter != null;

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
                    : (showLandmarkGlow
                        ? Colors.amber.shade200
                        : (isBoardStyle ? theme.boardColor : theme.rackColor)),
                border: Border.all(
                  color: showLandmarkGlow
                      ? Colors.amber.shade800
                      : (showPin ? Colors.amber.shade400 : (isBoardStyle ? theme.boardBorderColor : Colors.grey)),
                  width: showLandmarkGlow ? 2.5 : (showPin ? 2.5 : 1.5),
                ),
                borderRadius: isBoardStyle ? BorderRadius.circular(0.0) : BorderRadius.circular(8.0),
                boxShadow: showLandmarkGlow
                    ? [BoxShadow(color: Colors.amber.withOpacity(0.7), blurRadius: 6, spreadRadius: 1)]
                    : null,
              ),
              child: Stack(
                children: [
                  Center(
                    child: showLandmarkGlow
                        ? LayoutBuilder(
                            builder: (context, c) => Icon(Icons.star,
                                color: Colors.amber.shade900, size: (c.maxWidth * 0.5).clamp(10.0, 22.0)),
                          )
                        : letter != null
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
                              // Board tiles can be part of a placed word
                              // (long-press for a definition); rack tiles
                              // can be pinned instead, if enabled.
                              onLongPress: location.zone == TileZone.board
                                  ? () => _showDefinitionIfAny(context, ref, location.index)
                                  : (onTogglePin != null ? () => onTogglePin!(location.index) : null),
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
                  if (showPin)
                    Positioned(
                      top: 1,
                      right: 1,
                      child: Icon(Icons.push_pin, size: (fontSize * 0.5).clamp(8.0, 14.0), color: Colors.amber.shade900),
                    ),
                ],
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
            controller.moveTile(details.data, location, preferBalancedRefill: preferBalancedRefill);
          },
        );
      },
    );
  }
}

// Renders the board as a `boardWidth`-column square grid, pannable/
// zoomable via InteractiveViewer (so a larger-than-phone board, like
// Infinite Estate's, still fits and stays usable on any screen size).
// `boundaryMargin`/`minScale` are configurable so a mode with a much
// larger board (Infinite Estate) can allow zooming further out and
// panning further past the edges, making the space feel more expansive.
class GridBoardView extends ConsumerWidget {
  const GridBoardView({
    super.key,
    this.theme = GridTheme.classic,
    this.minScale = 0.2,
    this.maxScale = 2.5,
    this.boundaryMargin = EdgeInsets.zero,
    this.landmarkIndices = const {},
    this.preferBalancedRefill = false,
    this.transformController,
  });

  final GridTheme theme;
  final double minScale;
  final double maxScale;
  final EdgeInsets boundaryMargin;
  // Board indices to render as landmark spots (empty ones get a glow/star
  // -- see GridTileWidget.isLandmark). Empty by default for every mode
  // except Infinite Estate/Village, which passes its own set.
  final Set<int> landmarkIndices;
  // Farm structure ability -- see GridGameController.moveTile.
  final bool preferBalancedRefill;
  // Bridge structure ability: lets the caller programmatically pan/zoom
  // (e.g. jump to a landmark) by driving this controller. Null (the
  // default, every other mode) lets InteractiveViewer manage its own
  // internal controller as usual -- passing one in doesn't change
  // anything about normal manual pan/zoom, it just also allows external
  // control.
  final TransformationController? transformController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gridGameControllerProvider.select((s) => s.config));
    return InteractiveViewer(
      transformationController: transformController,
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
              return Padding(
                padding: EdgeInsets.zero,
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: GridTileWidget(
                    location: TileLocation(TileZone.board, index),
                    isBoardStyle: true,
                    isLandmark: landmarkIndices.contains(index),
                    theme: theme,
                    preferBalancedRefill: preferBalancedRefill,
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
  const GridRackView({
    super.key,
    this.crossAxisCount = 7,
    this.theme = GridTheme.classic,
    this.pinnedIndices = const {},
    this.onTogglePin,
  });

  final int crossAxisCount;
  final GridTheme theme;
  // Rack pinning (Infinite Estate/Village only -- see GridTileWidget.isPinned).
  final Set<int> pinnedIndices;
  final ValueChanged<int>? onTogglePin;

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
                  theme: theme,
                  isPinned: pinnedIndices.contains(index),
                  onTogglePin: onTogglePin,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
