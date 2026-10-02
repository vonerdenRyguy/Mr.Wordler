import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' show Quad, Vector3;

import '../dictionary/definition_service.dart';
import 'grid_providers.dart';
import 'letter_tile.dart';
import 'tile_location.dart';
import 'word_landing.dart';
import 'word_landing_banner.dart';
import '../ui/tokens.dart';

// The (possibly rotated) Quad InteractiveViewer.builder reports isn't
// axis-aligned in general, but our board never rotates, so the bounding
// box of its four corners is exactly the visible rectangle in content
// coordinates. Shared by GridBoardView and VillageBoardView's lazy paths.
Rect axisAlignedBoundingBox(Quad quad) {
  double xMin = quad.point0.x, xMax = quad.point0.x;
  double yMin = quad.point0.y, yMax = quad.point0.y;
  for (final Vector3 point in [quad.point1, quad.point2, quad.point3]) {
    if (point.x < xMin) xMin = point.x;
    if (point.x > xMax) xMax = point.x;
    if (point.y < yMin) yMin = point.y;
    if (point.y > yMax) yMax = point.y;
  }
  return Rect.fromLTRB(xMin, yMin, xMax, yMax);
}

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

// Board/rack color theme. Defaults are the 10x10 modes' token colors; a
// mode can pass its own (e.g. Infinite Estate's grass field) without
// affecting the others, since they all share this widget.
class GridTheme {
  final Color boardColor;
  final Color rackColor;
  final Color boardBorderColor;

  const GridTheme({
    this.boardColor = WColors.boardCell,
    this.rackColor = WColors.soilDeep,
    this.boardBorderColor = WColors.boardBed,
  });

  static const classic = GridTheme();
}

// One board cell or rack slot: a drag source/target holding the letter
// (if any) at `location`, drawn as a LetterTile that sizes itself to the
// slot, so it stays legible on a 10x10 phone board or a big tablet one.
class GridTileWidget extends ConsumerWidget {
  const GridTileWidget({
    super.key,
    required this.location,
    required this.isBoardStyle,
    this.theme = GridTheme.classic,
    this.isLandmark = false,
    this.isPinned = false,
    this.onTogglePin,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final letter = ref.watch(gridGameControllerProvider.select(
      (s) => (location.zone == TileZone.board ? s.boardCells : s.rackCells)[location.index],
    ));
    final controller = ref.read(gridGameControllerProvider.notifier);
    final isBoard = location.zone == TileZone.board;
    // Only the tiles a landing actually involves rebuild (see fxFor).
    final fx = isBoard ? ref.watch(tileLandingProvider.select((l) => fxFor(l, location.index))) : null;
    final showLandmarkGlow = isLandmark && letter == null;
    final showPin = !isBoard && isPinned && letter != null;

    // The cell is just the slot; the letter is drawn by LetterTile inside.
    BoxDecoration slotDecoration({required bool dropping}) {
      final radius = isBoardStyle ? BorderRadius.zero : BorderRadius.circular(8.0);
      if (dropping) {
        return BoxDecoration(
          color: Colors.blue.shade50,
          border: Border.all(color: Colors.blue.shade700, width: 3),
          borderRadius: radius,
        );
      }
      if (showLandmarkGlow) {
        return BoxDecoration(
          color: Colors.amber.shade200,
          border: Border.all(color: Colors.amber.shade800, width: 2.5),
          boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.7), blurRadius: 6, spreadRadius: 1)],
        );
      }
      if (isBoardStyle) {
        return BoxDecoration(
          color: theme.boardColor,
          border: Border.all(color: theme.boardBorderColor.withOpacity(0.25), width: 0.5),
        );
      }
      return BoxDecoration(
        color: theme.rackColor,
        border: Border.all(color: Colors.black.withOpacity(0.2), width: 1),
        borderRadius: radius,
      );
    }

    Widget placed(Widget tile) => isBoardStyle ? Padding(padding: const EdgeInsets.all(2), child: tile) : tile;

    return DragTarget<TileLocation>(
      builder: (context, candidateData, rejectedData) {
        final Widget content;
        if (showLandmarkGlow) {
          content = Center(
            child: LayoutBuilder(
              builder: (context, c) =>
                  Icon(Icons.star, color: Colors.amber.shade900, size: (c.maxWidth * 0.5).clamp(10.0, 22.0)),
            ),
          );
        } else if (letter != null) {
          content = Draggable<TileLocation>(
            data: location,
            // A fixed, big tile under the finger, so it stays readable
            // even when the board is zoomed far out.
            dragAnchorStrategy: (draggable, context, position) => const Offset(28, 28),
            feedback: Material(
              color: Colors.transparent,
              child: Transform.scale(
                scale: 1.1,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(blurRadius: 12, offset: const Offset(0, 6), color: Colors.black.withOpacity(0.3))],
                  ),
                  child: LetterTile(letter: letter),
                ),
              ),
            ),
            // A faint face shows where the tile came from.
            childWhenDragging: placed(LetterTile.ghost()),
            child: GestureDetector(
              // Board tiles can be part of a placed word (long-press for a
              // definition); rack tiles can be pinned instead, if enabled.
              onLongPress: isBoard
                  ? () => _showDefinitionIfAny(context, ref, location.index)
                  : (onTogglePin != null ? () => onTogglePin!(location.index) : null),
              child: placed(LetterTile(letter: letter, isBoard: isBoard, isPinned: showPin, fx: fx)),
            ),
          );
        } else {
          content = const SizedBox.expand();
        }
        return Container(
          decoration: slotDecoration(dropping: candidateData.isNotEmpty),
          child: content,
        );
      },
      onWillAcceptWithDetails: (details) {
        final currentLetter = (isBoard
            ? ref.read(gridGameControllerProvider).boardCells
            : ref.read(gridGameControllerProvider).rackCells)[location.index];
        return currentLetter == null;
      },
      onAcceptWithDetails: (details) {
        controller.moveTile(details.data, location);
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
    this.transformController,
    this.cellSize,
    this.cellGap = 0,
  });

  final GridTheme theme;
  final double minScale;
  final double maxScale;
  final EdgeInsets boundaryMargin;
  // Board indices to render as landmark spots (empty ones get a glow/star
  // -- see GridTileWidget.isLandmark). Empty by default for every mode
  // except Infinite Estate/Village, which passes its own set.
  final Set<int> landmarkIndices;
  // Bridge structure ability: lets the caller programmatically pan/zoom
  // (e.g. jump to a landmark) by driving this controller. Null (the
  // default, every other mode) lets InteractiveViewer manage its own
  // internal controller as usual -- passing one in doesn't change
  // anything about normal manual pan/zoom, it just also allows external
  // control.
  final TransformationController? transformController;
  // Null (the default, every mode except Infinite Estate/Village) keeps
  // the original behavior: the whole board is built eagerly and scaled
  // via AspectRatio to exactly fill the viewport -- fine for a 10x10
  // board, but building hundreds of thousands of widgets eagerly for a
  // much larger board would be janky/slow. A non-null cellSize switches
  // to InteractiveViewer.builder instead: each board cell is a fixed
  // `cellSize` logical pixels, laid out at its real (col*cellSize,
  // row*cellSize) position, and only cells that actually intersect the
  // current viewport are built -- so the board can be arbitrarily large
  // while only ever rendering a screenful of cells at a time.
  final double? cellSize;
  // Space between cells on the eager (10x10) path, so the board's bed
  // shows through as thin lines between them.
  final double cellGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gridGameControllerProvider.select((s) => s.config));

    // The word banner sits over the board but outside its zoom, so it's
    // always full size, on both the eager and the lazy path.
    Widget withBanner(Widget board) => Stack(
          fit: StackFit.passthrough,
          children: [
            board,
            const Positioned(top: 8, left: 0, right: 0, child: Center(child: WordLandingBanner())),
          ],
        );

    final size = cellSize;
    if (size == null) {
      return withBanner(InteractiveViewer(
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
                  padding: EdgeInsets.all(cellGap / 2),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: GridTileWidget(
                      location: TileLocation(TileZone.board, index),
                      isBoardStyle: true,
                      isLandmark: landmarkIndices.contains(index),
                      theme: theme,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ));
    }

    return withBanner(InteractiveViewer.builder(
      transformationController: transformController,
      boundaryMargin: boundaryMargin,
      minScale: minScale,
      maxScale: maxScale,
      builder: (context, viewport) {
        final visible = axisAlignedBoundingBox(viewport);
        final firstCol = (visible.left / size).floor().clamp(0, config.boardWidth - 1);
        final lastCol = (visible.right / size).ceil().clamp(0, config.boardWidth);
        final firstRow = (visible.top / size).floor().clamp(0, config.boardHeight - 1);
        final lastRow = (visible.bottom / size).ceil().clamp(0, config.boardHeight);

        return SizedBox(
          width: config.boardWidth * size,
          height: config.boardHeight * size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int row = firstRow; row < lastRow; row++)
                for (int col = firstCol; col < lastCol; col++)
                  Positioned(
                    left: col * size,
                    top: row * size,
                    width: size,
                    height: size,
                    child: GridTileWidget(
                      location: TileLocation(TileZone.board, row * config.boardWidth + col),
                      isBoardStyle: true,
                      isLandmark: landmarkIndices.contains(row * config.boardWidth + col),
                      theme: theme,
                    ),
                  ),
            ],
          ),
        );
      },
    ));
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
    this.childAspectRatio = 0.7,
    this.bordered = true,
    this.cellPadding = 4.0,
  });

  final int crossAxisCount;
  // False when the caller draws its own frame around the rack.
  final bool bordered;
  final double cellPadding;
  // Width/height of each rack cell. Every 10x10 mode keeps the original
  // 0.7 (tall cells inside a fixed-flex rack area); Infinite Estate passes
  // 1.0 and lets the rack size itself to its content so all of its rows
  // always fit instead of being cut off.
  final double childAspectRatio;
  final GridTheme theme;
  // Rack pinning (Infinite Estate/Village only -- see GridTileWidget.isPinned).
  final Set<int> pinnedIndices;
  final ValueChanged<int>? onTogglePin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // rackCells.length rather than config.rackSize: the rack can hold
    // extra bonus slots beyond its base size (see drawBonusLetter).
    final rackSize = ref.watch(gridGameControllerProvider.select((s) => s.rackCells.length));
    return Container(
      decoration: bordered ? BoxDecoration(border: Border.all(color: Colors.black, width: 2.0)) : null,
      child: Center(
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          shrinkWrap: true,
          children: List.generate(rackSize, (index) {
            return Padding(
              padding: EdgeInsets.all(cellPadding),
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
