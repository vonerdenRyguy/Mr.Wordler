import 'dart:math';

import 'package:flutter/material.dart';

import '../ui/tokens.dart';

// The eight village buildings, drawn in code (spec-14, canvas boards
// H141-H142). A building covers its word's whole run of letter blocks:
// walls from the first letter to the last, a window above each letter and
// the door above the middle one. Nothing here knows about the board; it
// draws in "iso units" through a projection [IsoProject]:
//   c runs along the board's columns, r along its rows (cell edges at
//   whole and half numbers are up to the caller), z is pixels up.

typedef IsoProject = Offset Function(double c, double r, double z);

const _ink = WColors.ink;
const _shade = Color(0x593B2A1E);

/// Where a building stands: its run of cells, as cell-edge coordinates.
class BuildingSpot {
  const BuildingSpot({
    required this.c0,
    required this.r0,
    required this.length,
    required this.across,
    required this.z0,
    required this.k,
  });

  /// The back corner of the first cell (cell-edge coordinates).
  final double c0;
  final double r0;
  final int length;

  /// Across words run along c, down words along r.
  final bool across;

  /// Height of the block tops the building stands on, in pixels.
  final double z0;

  /// Size factor: 1 = the 60px-wide tiles the designs were drawn at.
  final double k;
}

/// How tall a building's highest point is above its blocks, in pixels at
/// [k], for hit testing and culling.
double buildingTopHeight(String word, double k) {
  const w = 30.0, r = 22.0;
  switch (word) {
    case 'TOWER':
      return (w * 3 + r * 1.6 + 16) * k;
    case 'FARM':
      return (w * 1.9 + r * 0.8) * k;
    case 'WELL':
      return (w * 0.45 + w * 1.1 + r * 0.8) * k;
    case 'BRIDGE':
      return 32 * k;
    case 'GARDEN':
      return 50 * k;
    case 'BARN':
      return (w * 1.05 + r * 1.1) * k;
    case 'MILL':
      return (w + r + 30) * k;
    default:
      return (w + r + 20) * k;
  }
}

/// Draws [word]'s building at [spot]. Unknown words draw a plain house.
void paintBuilding(Canvas canvas, String word, BuildingSpot spot, IsoProject p) {
  _BuildingPainter(canvas, spot, p).paint(word);
}

class _BuildingPainter {
  _BuildingPainter(this.canvas, this.spot, this.p);

  final Canvas canvas;
  final BuildingSpot spot;
  final IsoProject p;

  double get k => spot.k;
  bool get across => spot.across;
  int get n => spot.length;
  double get sw => 2 * max(1.0, k * 0.8);

  // ---- drawing primitives ----
  void poly(List<Offset> pts, Color fill, {double? width}) {
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width ?? sw
          ..strokeJoin = StrokeJoin.round
          ..color = _ink);
  }

  void line(Offset a, Offset b, Color color, double width) {
    canvas.drawLine(
        a,
        b,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round);
  }

  void dot(Offset c, double radius, Color fill) {
    canvas.drawCircle(c, radius, Paint()..color = fill);
    canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw * 0.6
          ..color = _ink);
  }

  // A point along the word: [a] cells from its start, [b] across its width
  // (0 = back edge, 1 = front edge).
  Offset at(double a, double b, double z) => across ? p(spot.c0 + a, spot.r0 + b, z) : p(spot.c0 + b, spot.r0 + a, z);

  // ---- parts, all in word coordinates (a along, b across) ----

  /// A box from a0..a1 along the word and b0..b1 across it.
  void box(double a0, double b0, double a1, double b1, double z0, double h, Color front, Color side, [Color? top]) {
    // The long face toward the viewer and the end face toward the viewer.
    if (across) {
      poly([at(a0, b1, z0 + h), at(a1, b1, z0 + h), at(a1, b1, z0), at(a0, b1, z0)], front);
      poly([at(a1, b0, z0 + h), at(a1, b1, z0 + h), at(a1, b1, z0), at(a1, b0, z0)], side);
    } else {
      // Down: the near end is at a1 facing down-left, the long face at b1.
      poly([at(a1, b0, z0 + h), at(a1, b1, z0 + h), at(a1, b1, z0), at(a1, b0, z0)], front);
      poly([at(a0, b1, z0 + h), at(a1, b1, z0 + h), at(a1, b1, z0), at(a0, b1, z0)], side);
    }
    if (top != null) poly([at(a0, b0, z0 + h), at(a1, b0, z0 + h), at(a1, b1, z0 + h), at(a0, b1, z0 + h)], top);
  }

  /// Walls plus a gable roof whose ridge runs along the word.
  void gable(double a0, double b0, double a1, double b1, double z0, double wallH, double roofH, Color wall,
      Color wallDark, Color roof, Color roofDark) {
    const o = 0.14;
    final zt = z0 + wallH, zr = zt + roofH, bm = (b0 + b1) / 2;
    // Back slope (mostly hidden), long wall, end wall with its gable,
    // front slope with two shingle rows.
    poly([at(a0 - o, b0 - o, zt), at(a1 + o, b0 - o, zt), at(a1 + o, bm, zr), at(a0 - o, bm, zr)], roofDark);
    final longWall = [at(a0, b1, z0), at(a1, b1, z0), at(a1, b1, zt), at(a0, b1, zt)];
    final endWall = [at(a1, b0, z0), at(a1, b1, z0), at(a1, b1, zt), at(a1, bm, zr), at(a1, b0, zt)];
    poly(longWall, across ? wall : wallDark);
    poly(endWall, across ? wallDark : wall);
    poly([at(a0 - o, b1 + o, zt), at(a1 + o, b1 + o, zt), at(a1 + o, bm, zr), at(a0 - o, bm, zr)], roof);
    for (final t in [0.33, 0.66]) {
      final b = b1 + o + (bm - b1 - o) * t, z = zt + roofH * t;
      line(at(a0 - o + 0.05, b, z), at(a1 + o - 0.05, b, z), _shade, 1.5 * k);
    }
  }

  void pyramid(double a0, double b0, double a1, double b1, double z, double h, Color col, Color colDark) {
    const o = 0.08;
    final apex = at((a0 + a1) / 2, (b0 + b1) / 2, z + h);
    final nearSide = [at(a0 - o, b1 + o, z), at(a1 + o, b1 + o, z), apex];
    final nearEnd = [at(a1 + o, b0 - o, z), at(a1 + o, b1 + o, z), apex];
    poly(nearSide, across ? col : colDark);
    poly(nearEnd, across ? colDark : col);
  }

  /// A window or door on the long wall, a0..a1 along the word.
  void opening(double a0, double a1, double z0, double z1, Color fill) {
    poly([at(a0, 1 - 0.06, z0), at(a1, 1 - 0.06, z0), at(a1, 1 - 0.06, z1), at(a0, 1 - 0.06, z1)], fill,
        width: sw * 0.9);
  }

  /// One window per letter, the door on [door] (default the middle).
  void windows(int count, double z0, double wallH,
      {int? door, Color doorColor = const Color(0xFF4C7FB8), Color win = const Color(0xFFBFE6F7), bool barnX = false}) {
    final d = door ?? (count - 1) ~/ 2;
    for (int i = 0; i < count; i++) {
      if (i == d) {
        opening(i + 0.3, i + 0.7, z0, z0 + wallH * 0.72, doorColor);
        if (barnX) {
          line(at(i + 0.3, 0.94, z0), at(i + 0.7, 0.94, z0 + wallH * 0.72), const Color(0xFFFFF6E0), 2 * k);
          line(at(i + 0.7, 0.94, z0), at(i + 0.3, 0.94, z0 + wallH * 0.72), const Color(0xFFFFF6E0), 2 * k);
        }
      } else {
        opening(i + 0.3, i + 0.7, z0 + wallH * 0.32, z0 + wallH * 0.78, win);
      }
    }
  }

  void tree(double a, double b, double z, double s) {
    final g = at(a, b, z);
    final t = k * s;
    final trunk = Rect.fromLTWH(g.dx - 2.5 * t, g.dy - 16 * t, 5 * t, 16 * t);
    canvas.drawRect(trunk, Paint()..color = const Color(0xFF8A5A3C));
    canvas.drawRect(
        trunk,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw * 0.7
          ..color = _ink);
    dot(g - Offset(0, 24 * t), 13 * t, const Color(0xFF5E9E3A));
    canvas.drawCircle(g - Offset(4 * t, 28 * t), 4 * t, Paint()..color = const Color(0xFF7DBB52));
  }

  // ---- the eight ----
  void paint(String word) {
    const e = 0.06;
    final a0 = e, a1 = n - e, b0 = e, b1 = 1 - e;
    final z0 = spot.z0;
    final w = 30 * k, r = 22 * k;
    switch (word) {
      case 'BARN':
        gable(a0, b0, a1, b1, z0, w * 1.05, r * 1.1, const Color(0xFFC8442F), const Color(0xFFA63E28),
            const Color(0xFF6B4A35), const Color(0xFF4E3526));
        windows(n, z0, w * 1.05, barnX: true, doorColor: const Color(0xFF8F3322), win: const Color(0xFFFFF6E0));
      case 'FARM':
        gable(a0, b0, n - 1 - e, b1, z0, w * 0.9, r, const Color(0xFFFBE7B5), const Color(0xFFE8CF95),
            const Color(0xFF5E9E3A), const Color(0xFF437A28));
        windows(n - 1, z0, w * 0.9, door: min(1, n - 2));
        const m = 0.12;
        box(n - 1 + e + m, b0 + m, a1 - m, b1 - m, z0, w * 1.9, const Color(0xFFE6E1D6), const Color(0xFFC9C2B4));
        pyramid(n - 1 + e + m, b0 + m, a1 - m, b1 - m, z0 + w * 1.9, r * 0.8, const Color(0xFF5E9E3A),
            const Color(0xFF437A28));
      case 'TOWER':
        gable(a0, b0, n - 1 - e, b1, z0, w * 0.85, r * 0.8, const Color(0xFFE3DCCD), const Color(0xFFC9C0AE),
            const Color(0xFF4C7FB8), const Color(0xFF3A6391));
        windows(n - 1, z0, w * 0.85, door: min(1, n - 2), doorColor: const Color(0xFF8A5A3C));
        final th = w * 3;
        box(n - 1 + e, b0, a1, b1, z0, th, const Color(0xFFE3DCCD), const Color(0xFFC9C0AE));
        opening(n - 0.65, n - 0.35, z0 + th * 0.55, z0 + th * 0.8, const Color(0xFFBFE6F7));
        pyramid(n - 1 + e, b0, a1, b1, z0 + th, r * 1.6, const Color(0xFF4C7FB8), const Color(0xFF3A6391));
        final tip = at(n - 0.5, 0.5, z0 + th + r * 1.6);
        line(tip, tip - Offset(0, 14 * k), _ink, sw);
        poly([
          tip - Offset(0, 14 * k),
          tip - Offset(-11 * k, 10 * k),
          tip - Offset(0, 6 * k),
        ], WColors.sun, width: sw * 0.7);
      case 'MILL':
        gable(a0, b0, a1, b1, z0, w, r, const Color(0xFFD8CFC0), const Color(0xFFBDB2A0), const Color(0xFF8A5A3C),
            const Color(0xFF6B4530));
        windows(n, z0, w, door: 0, doorColor: const Color(0xFF8A5A3C));
        final hub = at(a1 + 0.02, 0.5, z0 + w + r * 0.35);
        final len = 46 * k;
        for (final deg in [20, 110, 200, 290]) {
          final ang = deg * pi / 180;
          final dir = Offset(cos(ang), sin(ang));
          final nrm = Offset(-sin(ang), cos(ang)) * 6 * k;
          final from = hub + dir * len * 0.3, to = hub + dir * len;
          poly([from, to, to + nrm, from + nrm], const Color(0xFFFFF6E0), width: sw * 0.9);
          line(hub, to, _ink, sw * 1.25);
        }
        dot(hub, 4 * k, WColors.sun);
      case 'WELL':
        final bh = w * 0.45;
        box(a0, b0, a1, b1, z0, bh, const Color(0xFFC9C0AE), const Color(0xFFADA38F), const Color(0xFFC9C0AE));
        const i = 0.16;
        poly([
          at(a0 + i, b0 + i, z0 + bh),
          at(a1 - i, b0 + i, z0 + bh),
          at(a1 - i, b1 - i, z0 + bh),
          at(a0 + i, b1 - i, z0 + bh)
        ], const Color(0xFF7CC6E8), width: sw * 0.75);
        for (int j = 1; j < n; j++) {
          line(at(j.toDouble(), b1, z0), at(j.toDouble(), b1, z0 + bh), _shade, 1.5 * k);
        }
        final mid = n / 2, ph = w * 1.1;
        final ra0 = mid - 0.9, ra1 = mid + 0.9;
        for (final post in [at(ra0 + 0.05, 0.2, z0 + bh), at(ra1 - 0.15, 0.8, z0 + bh)]) {
          poly([
            post - Offset(2.5 * k, 0),
            post + Offset(2.5 * k, 0),
            post + Offset(2.5 * k, -ph),
            post - Offset(2.5 * k, ph)
          ], const Color(0xFF8A5A3C), width: sw * 0.7);
        }
        gable(ra0, b0 + 0.1, ra1, b1 - 0.1, z0 + bh + ph, 0, r * 0.8, const Color(0xFF8A5A3C), const Color(0xFF6B4530),
            const Color(0xFFD9573B), const Color(0xFFA63E28));
        final bucket = at(mid, 0.5, z0 + bh + ph * 0.45);
        line(bucket - Offset(0, ph * 0.5), bucket, _ink, sw * 0.7);
        poly([
          bucket - Offset(5 * k, 0),
          bucket + Offset(5 * k, 0),
          bucket + Offset(5 * k, 9 * k),
          bucket + Offset(-5 * k, 9 * k)
        ], const Color(0xFF8A5A3C), width: sw * 0.7);
      case 'BRIDGE':
        final dh = 7 * k;
        box(a0 - 0.04, b0, a1 + 0.04, b1, z0, dh, const Color(0xFFB07A4E), const Color(0xFF8F6040),
            const Color(0xFFC98F5E));
        for (int j = 1; j < n * 2; j++) {
          line(at(j / 2, b0, z0 + dh), at(j / 2, b1, z0 + dh), const Color(0x663B2A1E), 1.2 * k);
        }
        final rh = 18 * k;
        for (final side in [0.1, 0.9]) {
          for (int j = 0; j <= n; j++) {
            final a = j.clamp(0.05, n - 0.05).toDouble();
            final foot = at(a, side, z0 + dh);
            line(foot, foot - Offset(0, rh), _ink, 3.5 * k);
            line(foot, foot - Offset(0, rh), const Color(0xFFC98F5E), 1.8 * k);
          }
          final s0 = at(0.05, side, z0 + dh + rh), s1 = at(n - 0.05, side, z0 + dh + rh);
          line(s0, s1, _ink, 5 * k);
          line(s0, s1, const Color(0xFFC98F5E), 2.5 * k);
        }
        for (final end in [0.1, n - 0.1]) {
          dot(at(end, 0.9, z0 + dh + rh + 6 * k), 4.5 * k, WColors.sun);
        }
      case 'GARDEN':
        final hh = 11 * k;
        const t = 0.2;
        const hedge = Color(0xFF5E9E3A), hedgeDark = Color(0xFF437A28), hedgeTop = Color(0xFF7DBB52);
        poly([at(a0, b0, z0), at(a1, b0, z0), at(a1, b1, z0), at(a0, b1, z0)], const Color(0xFF9C6B45),
            width: sw * 0.75);
        box(a0, b0, a1, b0 + t, z0, hh, hedge, hedgeDark, hedgeTop);
        box(a0, b0, a0 + t, b1, z0, hh, hedge, hedgeDark, hedgeTop);
        const colors = [Color(0xFFF28FB0), WColors.sun, Color(0xFFFFFFFF), Color(0xFFD9573B), Color(0xFFB98CE0)];
        for (int j = 0; j < n; j++) {
          for (final (u, v, ci) in [(0.35, 0.4, 0), (0.65, 0.65, 1), (0.5, 0.25, 2)]) {
            dot(at(j + u, v, z0 + 4 * k), 2.7 * k, colors[(ci + j) % colors.length]);
          }
        }
        tree(n - 0.8, 0.5, z0, 1.1);
        box(a0, b1 - t, a1, b1, z0, hh, hedge, hedgeDark, hedgeTop);
        box(a1 - t, b0, a1, b1, z0, hh, hedge, hedgeDark, hedgeTop);
        final gate = at(n ~/ 2 + 0.5, b1, z0 + hh);
        final arch = Path()
          ..moveTo(gate.dx - 10 * k, gate.dy + 2)
          ..relativeLineTo(0, -14 * k)
          ..relativeArcToPoint(Offset(20 * k, 0), radius: Radius.circular(10 * k))
          ..relativeLineTo(0, 14 * k);
        canvas.drawPath(
            arch,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4.5 * k
              ..color = _ink);
        canvas.drawPath(
            arch,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 * k
              ..color = const Color(0xFFFFF6E0));
        dot(gate - Offset(5 * k, 26 * k), 2.7 * k, const Color(0xFFF28FB0));
        dot(gate - Offset(-5 * k, 26 * k), 2.7 * k, const Color(0xFFF28FB0));
      default: // HOUSE and anything new
        gable(a0, b0, a1, b1, z0, w, r, const Color(0xFFFFF6E0), const Color(0xFFEAD9B8), const Color(0xFFD9573B),
            const Color(0xFFA63E28));
        windows(n, z0, w);
        final ca = max(0.0, n - 1.2);
        box(ca, 0.35, ca + 0.22, 0.57, z0 + w + r * 0.4, r * 0.9, const Color(0xFFC8442F), const Color(0xFFA63E28),
            const Color(0xFF8F3322));
    }
  }
}
