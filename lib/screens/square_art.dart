import 'dart:math';

import 'package:flutter/material.dart';

import '../online/town_square.dart';
import '../ui/tokens.dart';

// The Town Square's buildings, drawn in code (spec-13; real art later).
// Each stands on the ground the way village buildings do since spec-13: a
// soft contact shadow under it, no pedestal. A building that isn't finished
// is drawn pale behind wooden scaffolding with a pile of bricks.

/// One Town Square building. [built] is 1 when finished; less shows it
/// going up.
class SquareBuildingArt extends StatelessWidget {
  const SquareBuildingArt({super.key, required this.id, this.built = 1, this.size = 96});

  final String id;
  final double built;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: SquareBuildingPainter(id: id, built: built)),
    );
  }
}

class SquareBuildingPainter extends CustomPainter {
  SquareBuildingPainter({required this.id, this.built = 1});

  final String id;
  final double built;

  static const _ink = WColors.ink;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    final ground = Offset(s / 2, s * 0.88);

    // Contact shadow: soft, flat on the grass.
    canvas.drawOval(
      Rect.fromCenter(center: ground, width: s * 0.86, height: s * 0.2),
      Paint()
        ..color = const Color(0x403B2A1E)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );

    final done = built >= 1;
    if (!done) canvas.saveLayer(Offset.zero & Size(s, s), Paint()..color = const Color(0x80FFFFFF));
    switch (id) {
      case 'fountain':
        _fountain(canvas, s, ground);
      case 'bandstand':
        _bandstand(canvas, s, ground);
      case 'library':
        _library(canvas, s, ground);
      case 'garden':
        _garden(canvas, s, ground);
      case 'clocktower':
        _clockTower(canvas, s, ground);
      case 'bakery':
        _bakery(canvas, s, ground);
      default:
        _bakery(canvas, s, ground);
    }
    if (!done) {
      canvas.restore();
      _scaffold(canvas, s, ground, built.clamp(0.0, 1.0));
    }
    canvas.restore();
  }

  Paint _fill(Color c) => Paint()..color = c;
  Paint get _line => Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeJoin = StrokeJoin.round;

  void _shape(Canvas canvas, Path p, Color c) {
    canvas.drawPath(p, _fill(c));
    canvas.drawPath(p, _line);
  }

  Path _rect(double l, double t, double r, double b) => Path()..addRect(Rect.fromLTRB(l, t, r, b));

  void _fountain(Canvas canvas, double s, Offset g) {
    final basin = Rect.fromCenter(center: g.translate(0, -s * 0.06), width: s * 0.78, height: s * 0.26);
    // Basin wall, then the water on top.
    final wall = Path()
      ..moveTo(basin.left, basin.center.dy)
      ..lineTo(basin.left, basin.center.dy + s * 0.07)
      ..arcTo(basin.translate(0, s * 0.07), pi, -pi, false)
      ..lineTo(basin.right, basin.center.dy)
      ..close();
    _shape(canvas, wall, const Color(0xFFCFC3AE));
    _shape(canvas, Path()..addOval(basin), const Color(0xFFDCD2C0));
    _shape(canvas, Path()..addOval(basin.deflate(s * 0.04)), const Color(0xFF7CC4EA));
    // Column and bowl.
    _shape(canvas, _rect(g.dx - s * 0.05, g.dy - s * 0.4, g.dx + s * 0.05, g.dy - s * 0.08), const Color(0xFFDCD2C0));
    final bowl = Rect.fromCenter(center: Offset(g.dx, g.dy - s * 0.42), width: s * 0.36, height: s * 0.1);
    _shape(canvas, Path()..addOval(bowl), const Color(0xFFDCD2C0));
    // Water arcs.
    final water = Paint()
      ..color = const Color(0xFF4A90C8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.025
      ..strokeCap = StrokeCap.round;
    for (final dir in [-1.0, 1.0]) {
      final p = Path()
        ..moveTo(g.dx, g.dy - s * 0.56)
        ..quadraticBezierTo(g.dx + dir * s * 0.2, g.dy - s * 0.66, g.dx + dir * s * 0.27, g.dy - s * 0.12);
      canvas.drawPath(p, water);
    }
    canvas.drawLine(Offset(g.dx, g.dy - s * 0.46), Offset(g.dx, g.dy - s * 0.6), water);
  }

  void _bandstand(Canvas canvas, double s, Offset g) {
    final floor = Rect.fromCenter(center: g.translate(0, -s * 0.06), width: s * 0.8, height: s * 0.22);
    _shape(
        canvas, _rect(floor.left, floor.center.dy, floor.right, floor.center.dy + s * 0.07), const Color(0xFFB98A5A));
    _shape(canvas, Path()..addOval(floor), const Color(0xFFE3C9A0));
    // Posts.
    for (final x in [-0.32, -0.12, 0.12, 0.32]) {
      _shape(canvas, _rect(g.dx + s * x - s * 0.025, g.dy - s * 0.52, g.dx + s * x + s * 0.025, g.dy - s * 0.06),
          WColors.card);
    }
    // Red and cream roof.
    final roof = Path()
      ..moveTo(g.dx - s * 0.44, g.dy - s * 0.5)
      ..lineTo(g.dx, g.dy - s * 0.8)
      ..lineTo(g.dx + s * 0.44, g.dy - s * 0.5)
      ..quadraticBezierTo(g.dx, g.dy - s * 0.44, g.dx - s * 0.44, g.dy - s * 0.5)
      ..close();
    _shape(canvas, roof, const Color(0xFFC8553D));
    final stripe = Path()
      ..moveTo(g.dx - s * 0.1, g.dy - s * 0.47)
      ..lineTo(g.dx, g.dy - s * 0.8)
      ..lineTo(g.dx + s * 0.1, g.dy - s * 0.47)
      ..close();
    _shape(canvas, stripe, WColors.card);
    canvas.drawCircle(Offset(g.dx, g.dy - s * 0.82), s * 0.035, _fill(WColors.sun));
  }

  void _library(Canvas canvas, double s, Offset g) {
    final top = g.dy - s * 0.5;
    _shape(canvas, _rect(g.dx - s * 0.42, g.dy - s * 0.1, g.dx + s * 0.42, g.dy), const Color(0xFFCFC3AE));
    _shape(canvas, _rect(g.dx - s * 0.38, top, g.dx + s * 0.38, g.dy - s * 0.1), const Color(0xFFE8DCC4));
    for (final x in [-0.28, -0.1, 0.1, 0.28]) {
      _shape(canvas, _rect(g.dx + s * x - s * 0.035, top + s * 0.06, g.dx + s * x + s * 0.035, g.dy - s * 0.1),
          WColors.white);
    }
    final pediment = Path()
      ..moveTo(g.dx - s * 0.44, top)
      ..lineTo(g.dx, top - s * 0.2)
      ..lineTo(g.dx + s * 0.44, top)
      ..close();
    _shape(canvas, pediment, const Color(0xFF7A5C3E));
    // A book in the pediment.
    final book = Rect.fromCenter(center: Offset(g.dx, top - s * 0.065), width: s * 0.13, height: s * 0.07);
    _shape(canvas, Path()..addRect(book), const Color(0xFFC8553D));
    // Door.
    _shape(canvas, _rect(g.dx - s * 0.06, g.dy - s * 0.3, g.dx + s * 0.06, g.dy - s * 0.1), const Color(0xFF7A5C3E));
  }

  void _garden(Canvas canvas, double s, Offset g) {
    // Hedge ring with flowers, and a little arch.
    final bed = Rect.fromCenter(center: g.translate(0, -s * 0.06), width: s * 0.84, height: s * 0.28);
    _shape(canvas, Path()..addOval(bed), const Color(0xFF8B6B43));
    _shape(canvas, Path()..addOval(bed.deflate(s * 0.03)), const Color(0xFF4C9A52));
    final rnd = Random(id.hashCode);
    const petals = [Color(0xFFF59C86), Color(0xFFF6C443), WColors.white, Color(0xFFC9B3F0)];
    for (int i = 0; i < 12; i++) {
      final a = 2 * pi * i / 12;
      final c = Offset(bed.center.dx + cos(a) * bed.width * 0.36, bed.center.dy + sin(a) * bed.height * 0.32);
      canvas.drawCircle(c, s * 0.03, _fill(petals[rnd.nextInt(petals.length)]));
      canvas.drawCircle(c, s * 0.03, _line..strokeWidth = 1.2);
    }
    final arch = Path()
      ..moveTo(g.dx - s * 0.2, g.dy - s * 0.08)
      ..lineTo(g.dx - s * 0.2, g.dy - s * 0.48)
      ..arcToPoint(Offset(g.dx + s * 0.2, g.dy - s * 0.48), radius: Radius.circular(s * 0.2))
      ..lineTo(g.dx + s * 0.2, g.dy - s * 0.08);
    canvas.drawPath(
        arch,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.06);
    canvas.drawPath(
        arch,
        Paint()
          ..color = const Color(0xFF6FB25A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.035);
    for (final t in [0.15, 0.4, 0.6, 0.85]) {
      final a = pi + pi * t;
      canvas.drawCircle(Offset(g.dx + cos(a) * s * 0.2, g.dy - s * 0.48 + sin(a) * s * 0.2), s * 0.028,
          _fill(const Color(0xFFF59C86)));
    }
  }

  void _clockTower(Canvas canvas, double s, Offset g) {
    _shape(canvas, _rect(g.dx - s * 0.2, g.dy - s * 0.08, g.dx + s * 0.2, g.dy), const Color(0xFFCFC3AE));
    _shape(canvas, _rect(g.dx - s * 0.15, g.dy - s * 0.66, g.dx + s * 0.15, g.dy - s * 0.08), const Color(0xFFB9A7C9));
    final roof = Path()
      ..moveTo(g.dx - s * 0.2, g.dy - s * 0.66)
      ..lineTo(g.dx, g.dy - s * 0.92)
      ..lineTo(g.dx + s * 0.2, g.dy - s * 0.66)
      ..close();
    _shape(canvas, roof, const Color(0xFF5E4E70));
    final face = Offset(g.dx, g.dy - s * 0.5);
    canvas.drawCircle(face, s * 0.1, _fill(WColors.white));
    canvas.drawCircle(face, s * 0.1, _line);
    final hand = _line..strokeWidth = 2.4;
    canvas.drawLine(face, face.translate(0, -s * 0.07), hand);
    canvas.drawLine(face, face.translate(s * 0.05, 0), hand);
    _shape(canvas, _rect(g.dx - s * 0.05, g.dy - s * 0.25, g.dx + s * 0.05, g.dy - s * 0.08), const Color(0xFF5E4E70));
  }

  void _bakery(Canvas canvas, double s, Offset g) {
    final top = g.dy - s * 0.42;
    _shape(canvas, _rect(g.dx + s * 0.18, top - s * 0.28, g.dx + s * 0.28, top - s * 0.06), const Color(0xFFB0563A));
    _shape(canvas, _rect(g.dx - s * 0.36, top, g.dx + s * 0.36, g.dy), const Color(0xFFF2D58A));
    final roof = Path()
      ..moveTo(g.dx - s * 0.44, top + s * 0.02)
      ..lineTo(g.dx, top - s * 0.24)
      ..lineTo(g.dx + s * 0.44, top + s * 0.02)
      ..close();
    _shape(canvas, roof, const Color(0xFFB0563A));
    // Striped awning over the window.
    final aw = Rect.fromLTRB(g.dx - s * 0.32, g.dy - s * 0.3, g.dx + s * 0.04, g.dy - s * 0.22);
    for (int i = 0; i < 4; i++) {
      final w = aw.width / 4;
      canvas.drawRect(Rect.fromLTWH(aw.left + i * w, aw.top, w, aw.height),
          _fill(i.isEven ? const Color(0xFFC8553D) : WColors.white));
    }
    canvas.drawRect(aw, _line);
    _shape(canvas, _rect(g.dx - s * 0.28, g.dy - s * 0.22, g.dx, g.dy - s * 0.06), const Color(0xFFFFF3C4));
    _shape(canvas, _rect(g.dx + s * 0.1, g.dy - s * 0.26, g.dx + s * 0.26, g.dy), const Color(0xFF8A5A30));
  }

  /// Wooden poles, as many as the building has bricks for, and a pile of
  /// bricks at its foot.
  void _scaffold(Canvas canvas, double s, Offset g, double built) {
    final wood = Paint()
      ..color = const Color(0xFF9A6A3A)
      ..strokeWidth = s * 0.03
      ..strokeCap = StrokeCap.round;
    final left = g.dx - s * 0.38, right = g.dx + s * 0.38;
    final top = g.dy - s * (0.25 + 0.5 * built);
    canvas.drawLine(Offset(left, g.dy - s * 0.04), Offset(left, top), wood);
    canvas.drawLine(Offset(right, g.dy - s * 0.04), Offset(right, top), wood);
    for (double y = g.dy - s * 0.22; y > top; y -= s * 0.2) {
      canvas.drawLine(Offset(left, y), Offset(right, y), wood);
    }
    // Brick pile.
    const brick = Color(0xFFC0552F);
    final w = s * 0.11, h = s * 0.055;
    final base = Offset(g.dx + s * 0.2, g.dy + s * 0.01);
    for (int row = 0; row < 3; row++) {
      for (int i = 0; i < 3 - row; i++) {
        final r = Rect.fromLTWH(base.dx + (i - (3 - row) / 2) * w + row * 0, base.dy - (row + 1) * h, w, h);
        canvas.drawRect(r, _fill(brick));
        canvas.drawRect(r, _line..strokeWidth = 1.4);
      }
    }
  }

  @override
  bool shouldRepaint(SquareBuildingPainter oldDelegate) => oldDelegate.id != id || oldDelegate.built != built;
}

/// The family's little world: grass, trees, a packed-earth Town Square in
/// the middle with what's being built (or a vote sign), the finished
/// buildings around it, and each member's plot further out.
class SquareGroundPainter extends CustomPainter {
  SquareGroundPainter({required this.plaza});

  /// Where the square's earth goes.
  final Rect plaza;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft packed earth, flush with the grass, with a gentle edge.
    canvas.drawOval(
      plaza.inflate(8),
      Paint()
        ..color = const Color(0x55B89F72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawOval(plaza, Paint()..color = const Color(0xFFE2D2AC));
    canvas.drawOval(
      plaza.deflate(plaza.shortestSide * 0.12),
      Paint()..color = const Color(0xFFEADDBD),
    );
    // Grass tufts dotted about.
    final rnd = Random(7);
    final tuft = Paint()
      ..color = const Color(0xFF5E9E3A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 26; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      if (plaza.inflate(10).contains(p)) continue;
      for (final dx in [-3.0, 0.0, 3.0]) {
        canvas.drawLine(p, p.translate(dx, -6 - (dx == 0 ? 3 : 0)), tuft);
      }
    }
    // A few flowers.
    const colors = [Color(0xFFF59C86), Color(0xFFFFF6E0), Color(0xFFF6C443)];
    for (int i = 0; i < 12; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      if (plaza.inflate(10).contains(p)) continue;
      canvas.drawCircle(p, 3, Paint()..color = colors[i % colors.length]);
    }
  }

  @override
  bool shouldRepaint(SquareGroundPainter oldDelegate) => oldDelegate.plaza != plaza;
}

/// A round little tree.
class SquareTree extends StatelessWidget {
  const SquareTree({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _TreePainter()));
  }
}

class _TreePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final g = Offset(size.width / 2, size.height * 0.92);
    canvas.drawOval(
        Rect.fromCenter(center: g, width: s * 0.7, height: s * 0.16),
        Paint()
          ..color = const Color(0x403B2A1E)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.04));
    canvas.drawRect(
        Rect.fromLTRB(g.dx - s * 0.06, g.dy - s * 0.35, g.dx + s * 0.06, g.dy), Paint()..color = WColors.wood);
    canvas.drawCircle(Offset(g.dx, g.dy - s * 0.55), s * 0.32, Paint()..color = const Color(0xFF4C9A52));
    canvas.drawCircle(Offset(g.dx - s * 0.1, g.dy - s * 0.63), s * 0.14, Paint()..color = const Color(0xFF6FB25A));
  }

  @override
  bool shouldRepaint(_TreePainter oldDelegate) => false;
}

/// The colour of a Town Square building (for its chip and card).
Color squareColor(String? id) => Color(squareBuilding(id)?.color ?? 0xFF8A5A30);
