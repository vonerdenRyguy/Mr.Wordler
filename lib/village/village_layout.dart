import 'package:flutter/material.dart';

import '../explore/island_map.dart';
import '../ui/tokens.dart';
import '../villagers/villager_look.dart';
import 'structures.dart';

// What's left of the old angled Village view (removed in spec-22 C): where
// villagers may walk, the middle of the letters, and the villager figure the
// planet's streets draw.

/// The letters villagers may walk on: those that are not part of a building
/// word. A village with only buildings lets them walk on those instead.
Set<int> walkableCells(List<String?> boardCells, List<BoardStructure> structures) {
  final blocks = {for (final s in structures) ...s.ordered};
  final occupied = [
    for (var i = 0; i < boardCells.length; i++)
      if (boardCells[i] != null) i,
  ];
  final slabs = {for (final i in occupied) if (!blocks.contains(i)) i};
  return slabs.isNotEmpty ? slabs : occupied.toSet();
}

/// The middle of all letters as a cell; [emptyCell] (else the board's middle)
/// when there are none.
({int r, int c}) lettersCenter(List<String?> boardCells, int boardWidth, {int? emptyCell}) {
  var rs = 0, cs = 0, n = 0;
  for (var i = 0; i < boardCells.length; i++) {
    if (boardCells[i] == null) continue;
    rs += i ~/ boardWidth;
    cs += i % boardWidth;
    n++;
  }
  if (n == 0) {
    if (emptyCell != null) return (r: emptyCell ~/ boardWidth, c: emptyCell % boardWidth);
    final h = boardCells.length ~/ boardWidth;
    return (r: h ~/ 2, c: boardWidth ~/ 2);
  }
  return (r: (rs / n).round(), c: (cs / n).round());
}

/// A villager who has moved in, as the streets draw them.
class VillagerSprite {
  const VillagerSprite({required this.id, required this.name, this.best = false});
  final String id;
  final String name;
  final bool best;
}

/// A special tile not found yet (and a villager not met yet), drawn as a
/// faint outline through the fog.
class SpecialMarker {
  const SpecialMarker(this.cell, this.kind);
  final int cell;
  final SpecialKind kind;
}

/// The colour of an unfound special's outline.
Color specialMarkerColor(SpecialKind kind) => switch (kind) {
      SpecialKind.chest => const Color(0xFFFFC107),
      SpecialKind.goldenSquare => const Color(0xFFFFEB3B),
      SpecialKind.boulder => const Color(0xFF9E9E9E),
      SpecialKind.shrine => const Color(0xFFB06FFF),
      SpecialKind.landmark => const Color(0xFFFF8C42),
      SpecialKind.villager => const Color(0xFFE2557A),
    };

/// A small villager standing with their feet at [base] (placeholder art).
void paintVillagerFigure(Canvas canvas, Offset base, String id, String name,
    {bool best = false, bool faded = false}) {
  final opacity = faded ? 0.55 : 1.0;
  final body = (best ? const Color(0xFFE3A6C8) : (faded ? const Color(0xFFD7D0C4) : villagerColor(id))).withOpacity(opacity);
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = WColors.ink.withOpacity(opacity);
  canvas.drawOval(
    Rect.fromCenter(center: base + const Offset(0, 1), width: 26, height: 9),
    Paint()..color = const Color(0x33000000),
  );
  final torso = RRect.fromRectAndCorners(
    Rect.fromLTWH(base.dx - 10, base.dy - 22, 20, 22),
    topLeft: const Radius.circular(10),
    topRight: const Radius.circular(10),
    bottomLeft: const Radius.circular(4),
    bottomRight: const Radius.circular(4),
  );
  canvas.drawRRect(torso, Paint()..color = body);
  canvas.drawRRect(torso, outline);
  final head = Offset(base.dx, base.dy - 31);
  canvas.drawCircle(head, 10, Paint()..color = villagerSkin.withOpacity(opacity));
  canvas.drawCircle(head, 10, outline);
  final tp = TextPainter(
    text: TextSpan(
      text: villagerInitial(name),
      style: TextStyle(fontFamily: WFonts.display, fontSize: 13, color: WColors.ink.withOpacity(opacity), height: 1.0),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  tp.paint(canvas, head - Offset(tp.width / 2, tp.height / 2));
}
