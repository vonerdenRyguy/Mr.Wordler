import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/grid_board_widget.dart';
import '../game/grid_providers.dart';
import '../game/tile_location.dart';
import 'chunky_button.dart';
import 'tokens.dart';
import 'wordler_dialog.dart';

// The one layout for every 10x10 mode (Free Play, Time Attack, Daily,
// Theme Rush): a top bar (Leave, the mode's main pill, a letters-left
// chip), the wood-framed board, the soil rack sized to its content so it
// is always fully visible, and (except Theme Rush) the Swap / Check row.
// Must sit inside the mode's own grid ProviderScope.

/// The mode-colored pill in the top bar: a label and a big value.
class GamePill extends StatelessWidget {
  const GamePill({super.key, required this.label, required this.value, required this.color, this.alert = false});

  final String label;
  final String value;
  final Color color;
  // Last 30 seconds of a countdown: brick fill, white text.
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final text = alert ? WColors.white : WColors.ink;
    return Container(
      height: WSize.tapTarget - WSize.lip,
      margin: const EdgeInsets.only(bottom: WSize.lip),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: alert ? WColors.brick : color,
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: BorderRadius.circular(WSize.radiusButton),
        boxShadow: wLip(WSize.lip),
      ),
      child: Semantics(
        label: '$label $value',
        liveRegion: false,
        excludeSemantics: true,
        // On a crowded bar (small phone, big text) the label word is
        // dropped and the value shrinks to fit, rather than overflowing.
        child: LayoutBuilder(builder: (context, constraints) {
          final showLabel = label.isNotEmpty && constraints.maxWidth >= 120;
          return Row(
            children: [
              if (showLabel) ...[
                Text(label, style: WText.bodyBold.copyWith(fontSize: 15, color: text)),
                const SizedBox(width: WSize.gap2),
              ],
              Expanded(
                child: Align(
                  alignment: showLabel ? Alignment.centerRight : Alignment.center,
                  child:
                      FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: WText.number.copyWith(color: text))),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class GameLayout extends ConsumerWidget {
  const GameLayout({
    super.key,
    required this.onLeave,
    required this.pill,
    this.secondPill,
    this.showLettersLeft = true,
    this.giveUp,
    this.onCheck,
    this.showActions = true,
  });

  final VoidCallback onLeave;
  final Widget pill;
  // Theme Rush: the stopwatch, next to the theme pill.
  final Widget? secondPill;
  final bool showLettersLeft;
  // Daily only.
  final VoidCallback? giveUp;
  final VoidCallback? onCheck;
  // Theme Rush auto-checks and has no trade-in, so no action row.
  final bool showActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lettersLeft = ref.watch(gridGameControllerProvider.select((s) => s.rackCells.where((c) => c != null).length));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: WColors.paper,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(WSize.gamePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChunkyIconButton(icon: Icons.close, tooltip: 'Leave round', onPressed: onLeave),
                      const SizedBox(width: WSize.gap2),
                      Expanded(child: pill),
                      // Everything right of the pill shrinks a little on a
                      // very small phone with big text, instead of pushing
                      // the bar off screen; on a normal phone it's full size.
                      if (secondPill != null || showLettersLeft || giveUp != null)
                        // Not a flex child: a Flexible here would reserve its
                        // whole share even when the chips need less, starving
                        // the pill. Capped instead, so the pill gets the rest.
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: barWidth * 0.6),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (secondPill != null) ...[const SizedBox(width: WSize.gap2), secondPill!],
                                if (showLettersLeft) ...[
                                  const SizedBox(width: WSize.gap2),
                                  _LettersLeftChip(count: lettersLeft),
                                ],
                                if (giveUp != null) ...[
                                  const SizedBox(width: WSize.gap2),
                                  ChunkyButton(
                                      label: 'Give up',
                                      kind: ChunkyKind.danger,
                                      size: ChunkySize.small,
                                      onPressed: giveUp),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                }),
                const SizedBox(height: WSize.gap2),
                const Expanded(child: Center(child: _WoodFramedBoard())),
                const SizedBox(height: WSize.gap3),
                const _SoilRack(),
                if (showActions) ...[
                  const SizedBox(height: WSize.gap3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(flex: 4, child: SwapDropTarget()),
                      const SizedBox(width: WSize.gap3),
                      Expanded(
                        flex: 6,
                        child:
                            ChunkyButton(label: 'Check words', size: ChunkySize.big, expand: true, onPressed: onCheck),
                      ),
                    ],
                  ),
                  const Text('Drag a letter onto Swap to trade it in', style: WText.label, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LettersLeftChip extends StatelessWidget {
  const _LettersLeftChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count letters left',
      excludeSemantics: true,
      child: Container(
        height: WSize.tapTarget - WSize.lip,
        margin: const EdgeInsets.only(bottom: WSize.lip),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: WColors.card,
          border: Border.all(color: WColors.ink, width: WSize.outline),
          borderRadius: BorderRadius.circular(WSize.radiusButton),
          boxShadow: wLip(WSize.lip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Left', style: WText.label),
            const SizedBox(width: 6),
            Text('$count', style: WText.number.copyWith(fontSize: 24)),
          ],
        ),
      ),
    );
  }
}

class _WoodFramedBoard extends StatelessWidget {
  const _WoodFramedBoard();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: WSize.lipHero),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: WColors.wood,
          border: Border.all(color: WColors.ink, width: WSize.outline),
          borderRadius: BorderRadius.circular(16),
          boxShadow: wLip(WSize.lipHero),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const ColoredBox(
            color: WColors.boardBed,
            child: GridBoardView(cellGap: 2),
          ),
        ),
      ),
    );
  }
}

class _SoilRack extends StatelessWidget {
  const _SoilRack();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: WColors.soil,
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: BorderRadius.circular(18),
      ),
      // 3px per side = 6px gaps between slots.
      child: const GridRackView(childAspectRatio: 1.0, bordered: false, cellPadding: 3),
    );
  }
}

/// "Swap 1 for 3": the trade-in drop target. Not a button -- drag a rack
/// letter onto it. With too few open rack slots for 3 new letters it
/// explains why instead of silently refusing.
class SwapDropTarget extends ConsumerWidget {
  const SwapDropTarget({super.key});

  bool _hasRoom(WidgetRef ref, int index) {
    final rack = ref.read(gridGameControllerProvider).rackCells;
    var open = 0;
    for (int i = 0; i < rack.length; i++) {
      if (rack[i] == null || i == index) open++;
    }
    return open >= 3;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<TileLocation>(
      onWillAcceptWithDetails: (details) => details.data.zone == TileZone.rack,
      onAcceptWithDetails: (details) {
        final traded = ref.read(gridGameControllerProvider.notifier).tradeIn(details.data.index);
        if (!traded) {
          showWordlerDialog<void>(
            context,
            title: 'Not enough room',
            bodyText: 'Swapping gives you 3 new letters. Make room for them by placing a few letters first.',
            actions: [WordlerDialogAction('OK', () {})],
          );
        }
      },
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty && _hasRoom(ref, candidates.first!.index);
        return Semantics(
          label: 'Swap 1 for 3. Drag a rack letter here to trade it for 3 new letters.',
          excludeSemantics: true,
          child: Container(
            margin: const EdgeInsets.only(bottom: WSize.lip),
            child: CustomPaint(
              // Drawn over the fill, or the fill hides it.
              foregroundPainter: _DashedBorderPainter(solid: hovering),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56 - WSize.lip),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: hovering ? WColors.sky : WColors.skyTint,
                  borderRadius: BorderRadius.circular(WSize.radiusButton),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.swap_horiz, color: WColors.ink),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('Swap 1 for 3',
                          style: WText.button.copyWith(fontSize: 18, color: WColors.ink), textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.solid});

  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WColors.ink
      ..strokeWidth = WSize.outline
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(WSize.outline / 2),
      const Radius.circular(WSize.radiusButton),
    );
    final path = Path()..addRRect(rrect);
    if (solid) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 14) {
        canvas.drawPath(metric.extractPath(d, (d + 8).clamp(0, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => oldDelegate.solid != solid;
}

/// The Leave confirm for a 10x10 round, used by both the Leave button and
/// the system back gesture. [onLeave] stops the round's timer; the screen
/// is then popped back to Home.
Future<void> confirmLeaveRound(
  BuildContext context, {
  String title = 'Leave this round?',
  required String body,
  required VoidCallback onLeave,
}) {
  return showWordlerDialog<void>(
    context,
    title: title,
    bodyText: body,
    actions: [
      WordlerDialogAction('Keep playing', () {}),
      WordlerDialogAction('Leave', () {
        onLeave();
        Navigator.of(context).pop();
      }, kind: ChunkyKind.danger),
    ],
  );
}
