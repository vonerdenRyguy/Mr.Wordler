import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import 'globe_art.dart';
import 'port.dart';

const _plank = Color(0xFFB98752);
const _plankDark = Color(0xFF8A6A45);

/// One of the planet's small pictures as a widget (nothing until it loads).
class GlobeSpriteImage extends StatelessWidget {
  const GlobeSpriteImage(this.sprite, {super.key});
  final GlobeSprite sprite;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SpritePainter(sprite, GlobeArt.loaded));
}

class _SpritePainter extends CustomPainter {
  const _SpritePainter(this.sprite, this.art);
  final GlobeSprite sprite;
  final GlobeArt? art;

  @override
  void paint(Canvas canvas, Size size) {
    final a = art;
    if (a != null) paintGlobeSprite(canvas, a, sprite, Offset.zero & size);
  }

  @override
  bool shouldRepaint(_SpritePainter oldDelegate) => oldDelegate.sprite != sprite || oldDelegate.art != art;
}

void paintGlobeSprite(Canvas canvas, GlobeArt art, GlobeSprite sprite, Rect to) =>
    canvas.drawImageRect(art.sprites, sprite.rect, to, Paint()..filterQuality = FilterQuality.medium);

/// Words view: the port's picture on board square [index], or null.
Widget? portTile(Port port, int index) {
  if (index == port.boat) {
    return const IgnorePointer(
      child: OverflowBox(
        maxWidth: 88,
        maxHeight: 88,
        child: SizedBox.square(dimension: 88, child: GlobeSpriteImage(GlobeSprite.boatGold)),
      ),
    );
  }
  final at = port.pier.indexOf(index);
  if (at < 0) return null;
  return IgnorePointer(
    child: Semantics(
      label: at == 0 ? 'Your port' : null,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          CustomPaint(painter: _PlankPainter(lamp: at == 0 || at == 2)),
          if (index == port.flag)
            const OverflowBox(
              maxWidth: 72,
              maxHeight: 72,
              alignment: Alignment.bottomCenter,
              child: SizedBox.square(dimension: 72, child: GlobeSpriteImage(GlobeSprite.flagGold)),
            ),
        ],
      ),
    ),
  );
}

class _PlankPainter extends CustomPainter {
  const _PlankPainter({required this.lamp});
  final bool lamp;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = WColors.ink;
    for (var i = 0; i < 3; i++) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(1, h * i / 3 + 1, w - 2, h / 3 - 2), const Radius.circular(3));
      canvas.drawRRect(r, Paint()..color = i.isOdd ? _plankDark : _plank);
      canvas.drawRRect(r, edge);
    }
    if (lamp) {
      final c = Offset(w * 0.14, h * 0.2);
      canvas.drawCircle(c, w * 0.42, Paint()..color = const Color(0x55FFE08A));
      canvas.drawCircle(c, w * 0.14, Paint()..color = const Color(0xFFFFF3C4));
      canvas.drawCircle(c, w * 0.14, edge);
    }
  }

  @override
  bool shouldRepaint(_PlankPainter oldDelegate) => oldDelegate.lamp != lamp;
}

/// Village view: one pier square as planks on the water; [corners] are the
/// square's top, right, bottom and left.
void paintPierDiamond(Canvas canvas, List<Offset> corners, double width, {required bool lamp}) {
  final lift = Offset(0, -width * 0.10);
  final top = Path()..addPolygon([for (final c in corners) c + lift], true);
  final side = Path()
    ..addPolygon([corners[3], corners[2], corners[1], corners[1] + lift, corners[2] + lift, corners[3] + lift], true);
  canvas.drawPath(side, Paint()..color = _plankDark);
  canvas.drawPath(top, Paint()..color = _plank);
  final edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = WColors.ink;
  canvas.drawPath(top, edge);
  canvas.drawLine((corners[0] + corners[1]) / 2 + lift, (corners[3] + corners[2]) / 2 + lift, edge);
  if (lamp) {
    final foot = corners[3] + lift + Offset(width * 0.12, 0);
    final head = foot - Offset(0, width * 0.45);
    canvas.drawLine(foot, head, edge..strokeWidth = 3);
    canvas.drawCircle(head, width * 0.22, Paint()..color = const Color(0x55FFE08A));
    canvas.drawCircle(head, width * 0.08, Paint()..color = const Color(0xFFFFF3C4));
  }
}

/// The gold star's picture; [quiet] is the plain mark it leaves behind.
class GoldStarMark extends StatelessWidget {
  const GoldStarMark({super.key, this.quiet = false});
  final bool quiet;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Semantics(
          label: quiet ? 'Where your village began' : 'Gold star. Your first word must cover it.',
          child: CustomPaint(painter: _StarPainter(quiet)),
        ),
      );
}

class _StarPainter extends CustomPainter {
  const _StarPainter(this.quiet);
  final bool quiet;

  @override
  void paint(Canvas canvas, Size size) =>
      paintGoldStar(canvas, size.center(Offset.zero), size.shortestSide, quiet: quiet);

  @override
  bool shouldRepaint(_StarPainter oldDelegate) => oldDelegate.quiet != quiet;
}

void paintGoldStar(Canvas canvas, Offset c, double size, {bool quiet = false}) {
  if (!quiet) {
    final r = size * 0.95;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xE6FFE27A), Color(0x66FFD75E), Color(0x00FFD75E)],
          stops: [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }
  final star = Path();
  final outer = size * (quiet ? 0.28 : 0.4);
  const points = 5;
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : outer * 0.5;
    final p = c + Offset.fromDirection(-1.5707963 + i * 3.14159265 / points, r);
    i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
  }
  star.close();
  canvas.drawPath(star, Paint()..color = quiet ? const Color(0x99F6C443) : WColors.sun);
  if (!quiet) {
    canvas.drawPath(
      star,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.5
        ..color = WColors.ink,
    );
  }
}
