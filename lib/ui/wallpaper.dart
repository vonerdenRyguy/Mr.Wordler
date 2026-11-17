import 'package:flutter/material.dart';

import 'tokens.dart';

// The app's wallpapers (spec-14, canvas boards H143-H144). Drawn in code,
// so they're sharp at any size. Ryan's pick: the quiet pattern on list
// pages, the hills on the big pages.

enum WallpaperKind {
  /// "Letters and leaves": paper with a very faint pattern of letter tiles,
  /// hearts, leaves and little houses.
  pattern,

  /// "Home hills": sky fading into paper, rolling hills with little houses
  /// and a path at the bottom.
  hills,
}

/// A wallpaper filling its box, with [child] on top.
class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key, required this.kind, this.child});

  final WallpaperKind kind;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WallpaperPainter(kind),
      isComplex: true,
      child: child ?? const SizedBox.expand(),
    );
  }
}

/// [kind] painted as if the whole screen were behind this box, which sits
/// at the top or bottom of the screen ([top]). For the floating bars over
/// a page with a wallpaper, so they show the same picture.
class WallpaperSlice extends StatelessWidget {
  const WallpaperSlice({super.key, required this.kind, required this.top, required this.child});

  final WallpaperKind kind;
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return ClipRect(
      child: CustomPaint(
        painter: WallpaperPainter(kind, screen: screen, fromTop: top),
        child: child,
      ),
    );
  }
}

class WallpaperPainter extends CustomPainter {
  WallpaperPainter(this.kind, {this.screen, this.fromTop = true});

  final WallpaperKind kind;

  /// When set, paint as if the box were [screen]-sized, anchored at its top
  /// or bottom edge ([fromTop]).
  final Size? screen;
  final bool fromTop;

  @override
  void paint(Canvas canvas, Size size) {
    final full = screen ?? size;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (!fromTop) canvas.translate(0, size.height - full.height);
    switch (kind) {
      case WallpaperKind.pattern:
        _pattern(canvas, full);
      case WallpaperKind.hills:
        _hills(canvas, full);
    }
    canvas.restore();
  }

  static final _tilePainters = <String, TextPainter>{};

  static TextPainter _letter(String l) => _tilePainters.putIfAbsent(
        l,
        () => TextPainter(
          text: TextSpan(
            text: l,
            style: const TextStyle(fontFamily: WFonts.display, fontSize: 15, color: WColors.paperPattern, height: 1),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(),
      );

  void _pattern(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = WColors.paper);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = WColors.paperPattern;
    final fill = Paint()..color = WColors.paperPattern;
    const tile = 132.0;
    for (double y = 0; y < size.height; y += tile) {
      for (double x = 0; x < size.width; x += tile) {
        void at(double dx, double dy, double deg, void Function() draw) {
          canvas.save();
          canvas.translate(x + dx, y + dy);
          canvas.rotate(deg * 3.14159265 / 180);
          draw();
          canvas.restore();
        }

        void letterTile(String l) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(const Rect.fromLTWH(-11, -11, 22, 22), const Radius.circular(5)), stroke);
          final tp = _letter(l);
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2 + 1));
        }

        void heart() {
          canvas.drawPath(
              Path()
                ..moveTo(0, 6)
                ..cubicTo(-9, 0, -9, -7, -4, -8)
                ..cubicTo(-2, -8.4, -0.6, -7.2, 0, -6)
                ..cubicTo(0.6, -7.2, 2, -8.4, 4, -8)
                ..cubicTo(9, -7, 9, 0, 0, 6)
                ..close(),
              fill);
        }

        void leaf() {
          canvas.drawPath(
              Path()
                ..moveTo(-9, 0)
                ..cubicTo(-5, -8, 5, -8, 9, 0)
                ..cubicTo(5, 8, -5, 8, -9, 0)
                ..close(),
              stroke);
          canvas.drawLine(const Offset(-9, 0), const Offset(9, 0), stroke);
        }

        void house() {
          canvas.drawPath(
              Path()
                ..moveTo(-9, 9)
                ..lineTo(-9, -1)
                ..lineTo(0, -9)
                ..lineTo(9, -1)
                ..lineTo(9, 9)
                ..close()
                ..moveTo(-3, 9)
                ..lineTo(-3, 3)
                ..lineTo(3, 3)
                ..lineTo(3, 9),
              stroke);
        }

        at(22, 24, -8, () => letterTile('W'));
        at(88, 22, 10, heart);
        at(60, 66, -25, leaf);
        at(112, 80, 6, house);
        at(26, 102, 9, () => letterTile('A'));
        at(84, 116, -12, heart);
      }
    }
  }

  void _hills(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = w / 390;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [WColors.wallSky, WColors.paper],
          stops: const [0, 0.55],
        ).createShader(Offset.zero & size),
    );
    // Clouds near the top.
    for (final (x, y, k) in [(70.0, 90.0, 1.0), (300.0, 60.0, 0.8), (250.0, 200.0, 0.6)]) {
      _cloud(canvas, Offset(x * s, y * s), k * s);
    }
    // Hills hang from the bottom edge, drawn on the 390x844 design.
    canvas.save();
    canvas.translate(0, h - 844 * s);
    canvas.scale(s);
    Path hill(double y0, double c1x, double c1y, double c2x, double c2y, double mx, double my, double c3x, double c3y,
            double endY) =>
        Path()
          ..moveTo(0, y0)
          ..cubicTo(c1x, c1y, c2x, c2y, mx, my)
          ..cubicTo(mx + (mx - c2x), my + (my - c2y), c3x, c3y, 390, endY)
          ..lineTo(390, 844)
          ..lineTo(0, 844)
          ..close();
    canvas.drawPath(hill(640, 80, 600, 150, 610, 210, 630, 330, 650, 610), Paint()..color = WColors.hillFar);
    _house(canvas, const Offset(70, 618), WColors.brick, 0.9);
    _house(canvas, const Offset(320, 618), WColors.sky, 0.8);
    _tree(canvas, const Offset(110, 622), 0.8);
    _tree(canvas, const Offset(285, 624), 0.7);
    canvas.drawPath(hill(700, 70, 680, 140, 690, 200, 712, 320, 730, 690), Paint()..color = WColors.hillMid);
    _house(canvas, const Offset(170, 704), WColors.sun, 1);
    _house(canvas, const Offset(235, 712), WColors.grass, 0.95);
    _tree(canvas, const Offset(205, 712), 0.9);
    canvas.drawPath(
        Path()
          ..moveTo(150, 844)
          ..cubicTo(170, 790, 200, 760, 210, 712),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..color = WColors.path);
    canvas.drawPath(hill(770, 90, 750, 160, 765, 230, 785, 340, 800, 770), Paint()..color = WColors.hillNear);
    canvas.restore();
  }

  void _cloud(Canvas canvas, Offset c, double k) {
    final paint = Paint()..color = WColors.white.withOpacity(0.85);
    canvas.drawOval(Rect.fromCenter(center: c, width: 52 * k, height: 22 * k), paint);
    canvas.drawOval(Rect.fromCenter(center: c + Offset(-12 * k, -6 * k), width: 26 * k, height: 22 * k), paint);
    canvas.drawOval(Rect.fromCenter(center: c + Offset(10 * k, -9 * k), width: 30 * k, height: 26 * k), paint);
  }

  void _house(Canvas canvas, Offset at, Color roof, double k) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(k);
    final body = Path()
      ..moveTo(-9, 0)
      ..lineTo(-9, -11)
      ..lineTo(0, -19)
      ..lineTo(9, -11)
      ..lineTo(9, 0)
      ..close();
    canvas.drawPath(body, Paint()..color = WColors.card);
    canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = WColors.ink);
    canvas.drawPath(
        Path()
          ..moveTo(-12, -10)
          ..lineTo(0, -20)
          ..lineTo(12, -10),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = roof);
    canvas.drawRect(const Rect.fromLTWH(-2.5, -7, 5, 7), Paint()..color = WColors.ink);
    canvas.restore();
  }

  void _tree(Canvas canvas, Offset at, double k) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(k);
    canvas.drawRect(const Rect.fromLTWH(-2, -10, 4, 10), Paint()..color = WColors.wood);
    canvas.drawCircle(const Offset(0, -16), 9, Paint()..color = const Color(0xFF5E9E3A));
    canvas.drawCircle(
        const Offset(0, -16),
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = WColors.ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(WallpaperPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.screen != screen || oldDelegate.fromTop != fromTop;
}
