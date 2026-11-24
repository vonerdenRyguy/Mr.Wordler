import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import 'planet.dart';

// Pictures for the close-up (spec-22 C's phone test): letter blocks and the
// small things growing on the ground, each drawn once onto a sheet.

/// How close the close-up goes (about 40 pixels a square on a phone).
const double kCloseUpMaxZoom = 12;

const double kBlockCell = 96;

/// Top colours: plain words first, then building words.
const kBlockColors = [
  Color(0xFFFFF1CF),
  Color(0xFFFFB184),
  Color(0xFFFFDC62),
  Color(0xFF8FE0CE),
  Color(0xFFFFA3B5),
  Color(0xFFB9E27C),
];

ui.Image? _blocks;

/// One row per colour: A-Z, then the front side and the end side.
ui.Image blockSheet() => _blocks ??= _drawBlocks();

ui.Image _drawBlocks() {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var color = 0; color < kBlockColors.length; color++) {
    final base = kBlockColors[color];
    final hsl = HSLColor.fromColor(base);
    Color darker(double by) => hsl.withLightness((hsl.lightness - by).clamp(0.0, 1.0)).toColor();
    for (var i = 0; i < 28; i++) {
      final cell = Rect.fromLTWH(i * kBlockCell, color * kBlockCell, kBlockCell, kBlockCell);
      if (i >= 26) {
        canvas.drawRect(cell, Paint()..color = darker(i == 26 ? 0.22 : 0.32));
        continue;
      }
      canvas.drawRect(cell, Paint()..color = darker(0.30));
      canvas.drawRRect(RRect.fromRectAndRadius(cell.deflate(3), const Radius.circular(14)), Paint()..color = base);
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell.deflate(8), const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0x88FFFFFF),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(65 + i),
          style: const TextStyle(fontFamily: 'LilitaOne', fontSize: 72, color: WColors.ink),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      tp.paint(canvas, cell.center - Offset(tp.width / 2, tp.height / 2));
    }
  }
  return recorder.endRecording().toImageSync((28 * kBlockCell).round(), (kBlockColors.length * kBlockCell).round());
}

const double kBitCell = 64;

/// Which small thing grows on a square of [band] ([n] is 0-99); -1: nothing.
int groundBitFor(Band band, int n) => switch (band) {
      Band.sunnyShore => n < 4 ? 5 : -1,
      Band.meadow || Band.whisperWoods => n < 16 ? 0 : (n < 18 ? 1 : (n < 20 ? 2 : (n < 22 ? 3 : (n < 24 ? 4 : -1)))),
      Band.ruinHills => n < 8 ? 0 : (n < 14 ? 4 : -1),
      _ => -1,
    };

ui.Image? _bits;

/// Grass, pink, gold and white flowers, a pebble, a shell.
ui.Image groundBits() => _bits ??= _drawBits();

ui.Image _drawBits() {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  void shadow(double x, double w) =>
      canvas.drawOval(Rect.fromCenter(center: Offset(x, 57), width: w, height: 8), Paint()..color = const Color(0x332A4A12));
  void grass(double x) {
    for (final (dx, lean, h, color) in const [
      (-9.0, -10.0, 22.0, Color(0xFF4C9A35)),
      (9.0, 10.0, 22.0, Color(0xFF4C9A35)),
      (-2.0, -3.0, 32.0, Color(0xFF5FB542)),
      (4.0, 5.0, 27.0, Color(0xFF75C94F)),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x + dx - 5, 58)
          ..quadraticBezierTo(x + dx, 58 - h / 2, x + dx + lean, 58 - h)
          ..quadraticBezierTo(x + dx + 5, 58 - h / 2, x + dx + 5, 58)
          ..close(),
        Paint()..color = color,
      );
    }
  }

  for (var i = 0; i < 6; i++) {
    final x = i * kBitCell + kBitCell / 2;
    if (i == 0) {
      shadow(x, 34);
      grass(x);
    } else if (i <= 3) {
      shadow(x, 26);
      canvas.drawLine(
        Offset(x, 57),
        Offset(x, 30),
        Paint()
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF4C9A35),
      );
      final petal = [const Color(0xFFFF7FA8), const Color(0xFFFFC93C), const Color(0xFFFFFFFF)][i - 1];
      for (var k = 0; k < 5; k++) {
        final a = k * 2 * math.pi / 5;
        canvas.drawCircle(Offset(x + math.cos(a) * 9, 25 + math.sin(a) * 9), 7.5, Paint()..color = petal);
      }
      canvas.drawCircle(Offset(x, 25), 6, Paint()..color = i == 2 ? const Color(0xFFB9722E) : const Color(0xFFFFD75E));
    } else if (i == 4) {
      shadow(x, 34);
      canvas.drawOval(Rect.fromLTWH(x - 14, 36, 28, 21), Paint()..color = const Color(0xFF9D9A94));
      canvas.drawOval(Rect.fromLTWH(x - 10, 37, 17, 11), Paint()..color = const Color(0xFFC6C3BC));
    } else {
      shadow(x, 30);
      for (var k = -2; k <= 2; k++) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x + k * 5, 48), width: 9, height: 20),
          Paint()..color = k.isEven ? const Color(0xFFFFB9A0) : const Color(0xFFFFE0D0),
        );
      }
    }
  }
  return recorder.endRecording().toImageSync((6 * kBitCell).round(), kBitCell.round());
}
