import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../explore/fog.dart';
import '../explore/island_map.dart';
import '../ui/chunky_button.dart';
import '../ui/tokens.dart';

// ── Island Map ───────────────────────────────────────────────────────────────

/// A whole-island overview: rings, fog, found specials, and "Explored N%".
/// Tapping a spot switches to Words view centred there.
///
/// Shown as a full-screen dialog. [onJumpTo] receives the board cell index
/// the player tapped.
class IslandMapPage extends StatelessWidget {
  const IslandMapPage({
    super.key,
    required this.islandMap,
    required this.fog,
    required this.foundSpecialIds,
    required this.onJumpTo,
  });

  final IslandMap islandMap;
  final FogMap fog;
  final Set<String> foundSpecialIds;
  final void Function(int boardIndex) onJumpTo;

  @override
  Widget build(BuildContext context) {
    final explored = fog.exploredFraction(islandMap.reachableCellCount);
    final pct = (explored * 100).round().clamp(0, 100);

    return Material(
      color: const Color(0xFF1A1A2E),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  ChunkyIconButton(
                    icon: Icons.close,
                    tooltip: 'Close island map',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Text('Island Map', style: WText.heading.copyWith(color: WColors.white)),
                  const Spacer(),
                  _ExploredChip(percent: pct),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GestureDetector(
                  onTapUp: (details) {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    // Convert tap local offset to board index
                    final cellIndex = _tapToCell(
                      details.localPosition,
                      box.size,
                      islandMap,
                    );
                    if (cellIndex != null) {
                      Navigator.of(context).pop();
                      onJumpTo(cellIndex);
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CustomPaint(
                      painter: _IslandMapPainter(
                        islandMap: islandMap,
                        fog: fog,
                        foundSpecialIds: foundSpecialIds,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Tap a spot to jump there',
                style: WText.label.copyWith(color: WColors.muted),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int? _tapToCell(Offset localOffset, Size widgetSize, IslandMap map) {
    // The CustomPaint fills the GestureDetector's render box minus padding;
    // use 12px padding from each side.
    const pad = 12.0;
    final paintW = widgetSize.width - pad * 2;
    final paintH = widgetSize.height - pad * 2;
    final adjustedOffset = localOffset - const Offset(pad, pad);

    final bw = map.boardWidth;
    final bh = map.boardHeight;
    final homeR = map.homes.first ~/ bw;
    final homeC = map.homes.first % bw;
    const cellsShown = _IslandMapPainter.halfCells * 2;

    final scale = math.min(paintW, paintH) / cellsShown;
    final centerX = paintW / 2;
    final centerY = paintH / 2;

    final dc = ((adjustedOffset.dx - centerX) / scale).round();
    final dr = ((adjustedOffset.dy - centerY) / scale).round();

    final row = (homeR + dr).clamp(0, bh - 1);
    final col = (homeC + dc).clamp(0, bw - 1);
    return row * bw + col;
  }
}

class _ExploredChip extends StatelessWidget {
  const _ExploredChip({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A3A5E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WColors.muted.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.explore, color: WColors.sky, size: 16),
          const SizedBox(width: 4),
          Text(
            'Explored $percent%',
            style: WText.label.copyWith(color: WColors.white),
          ),
        ],
      ),
    );
  }
}

// ── Custom painter ────────────────────────────────────────────────────────────

class _IslandMapPainter extends CustomPainter {
  _IslandMapPainter({
    required this.islandMap,
    required this.fog,
    required this.foundSpecialIds,
  });

  final IslandMap islandMap;
  final FogMap fog;
  final Set<String> foundSpecialIds;

  /// Half-width of the visible area in board cells.
  static const halfCells = 95;

  static const Map<Ring, Color> _ringColors = {
    Ring.coast: Color(0xFF3366AA),
    Ring.mountains: Color(0xFF7A8A7A),
    Ring.hills: Color(0xFF8DB56A),
    Ring.river: Color(0xFF4A88CC),
    Ring.forest: Color(0xFF2D6A2D),
    Ring.meadow: Color(0xFF72C472),
  };

  // Chebyshev max distances for each ring (from island_map.dart constants).
  static const _ringMaxDist = {
    Ring.meadow: 12,
    Ring.forest: 28,
    Ring.river: 31,
    Ring.hills: 50,
    Ring.mountains: 75,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final bw = islandMap.boardWidth;
    final bh = islandMap.boardHeight;
    final homeR = islandMap.homes.first ~/ bw;
    final homeC = islandMap.homes.first % bw;

    const cellsShown = halfCells * 2;
    final scale = math.min(size.width, size.height) / cellsShown;
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 1. Fill background (coast/sea).
    canvas.drawRect(Offset.zero & size, Paint()..color = _ringColors[Ring.coast]!);

    // 2. Draw rings outward-to-inward using filled ovals.
    // Drawing order: Mountains → Hills → (redraw Hills to cover river outer edge) →
    // Forest outer circle → River band → Forest inner circle → Meadow.
    void drawRingOval(Ring ring, double maxDist) {
      final r = maxDist * scale;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 2, height: r * 2),
        Paint()..color = _ringColors[ring]!,
      );
    }

    drawRingOval(Ring.mountains, _ringMaxDist[Ring.mountains]!.toDouble());
    drawRingOval(Ring.hills, _ringMaxDist[Ring.hills]!.toDouble());
    // River: draw forest's outer circle up to riverMax, then overdraw with
    // forest colour inside forestMax (28), leaving the 29-31 band as river.
    drawRingOval(Ring.river, _ringMaxDist[Ring.river]!.toDouble()); // river colour
    drawRingOval(Ring.forest, _ringMaxDist[Ring.forest]!.toDouble()); // forest covers to 28
    drawRingOval(Ring.meadow, _ringMaxDist[Ring.meadow]!.toDouble());

    // 3. Fog overlay (sampled at 2-cell resolution for performance).
    final solidFogPath = Path();
    final hazeFogPath = Path();
    const step = 2;
    final stepPx = scale * step;
    for (int dr = -halfCells; dr < halfCells; dr += step) {
      for (int dc = -halfCells; dc < halfCells; dc += step) {
        final r = (homeR + dr).clamp(0, bh - 1);
        final c = (homeC + dc).clamp(0, bw - 1);
        final idx = r * bw + c;
        if (fog.isCleared(idx)) continue;
        final px = cx + dc * scale;
        final py = cy + dr * scale;
        final rect = Rect.fromLTWH(px, py, stepPx, stepPx);
        if (fog.canSee(idx)) {
          hazeFogPath.addRect(rect);
        } else {
          solidFogPath.addRect(rect);
        }
      }
    }
    canvas.drawPath(solidFogPath, Paint()..color = const Color(0xEE404060));
    canvas.drawPath(hazeFogPath, Paint()..color = const Color(0xAA404060));

    // 4. Special tile markers (visible through fog as faint outlines).
    for (final s in islandMap.specials) {
      final sr = s.cell ~/ bw;
      final sc = s.cell % bw;
      final dr = sr - homeR;
      final dc = sc - homeC;
      if (dr.abs() > halfCells || dc.abs() > halfCells) continue;
      final px = cx + dc * scale;
      final py = cy + dr * scale;
      final found = foundSpecialIds.contains(s.id);
      final cleared = fog.isCleared(s.cell);
      _paintSpecial(canvas, Offset(px, py), s.kind, found: found, visible: cleared || fog.canSee(s.cell));
    }

    // 5. Home marker (white dot).
    canvas.drawCircle(
      Offset(cx, cy),
      4,
      Paint()..color = Colors.white.withOpacity(0.9),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      4,
      Paint()
        ..color = WColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintSpecial(Canvas canvas, Offset center, SpecialKind kind, {required bool found, required bool visible}) {
    if (!visible && !found) return;
    final opacity = found ? 1.0 : (visible ? 0.6 : 0.2);
    final color = switch (kind) {
      SpecialKind.chest => Colors.amber,
      SpecialKind.goldenSquare => Colors.yellow,
      SpecialKind.boulder => Colors.grey,
      SpecialKind.shrine => const Color(0xFFB06FFF),
      SpecialKind.landmark => const Color(0xFFFF8C42),
    }.withOpacity(opacity);
    const r = 3.0;
    if (found) {
      canvas.drawCircle(center, r, Paint()..color = color);
    } else {
      canvas.drawCircle(center, r, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_IslandMapPainter old) =>
      old.fog != fog ||
      old.foundSpecialIds != foundSpecialIds;
}
