import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import 'planet.dart';

// Letterra's globe (spec-18, canvas W234 and X252). 2D only: an orthographic
// projection in a CustomPainter. The board's top-down disc IS the northern
// hemisphere: the Lantern is the North Pole, the Sunny Shore the equator, and
// harbor slot s sits at longitude s * 45 degrees. A cell at (lat, lon) is the
// board cell at distance d = (90 - lat) / 90 * 124 from the Lantern in the
// direction lon, so fog, bands and bays all come from the same board.
//
// Art is placeholder, drawn in code.

enum GlobeMode {
  /// Zoomed in on one harbor; the Lantern glows at the top.
  closeUp,

  /// The whole planet.
  whole,
}

/// One person's village as the globe draws it.
class GlobeVillage {
  const GlobeVillage({
    required this.slot,
    required this.name,
    this.buildings = const [],
    this.reach = 0,
    this.color = WColors.sun,
  });

  final int slot;
  final String name;

  /// Up to four of their building words (WELL, FARM...).
  final List<String> buildings;

  /// How far up they have climbed, as a [Band] index counted from the shore:
  /// 0 shore, 1 meadow, 2 woods, 3 river, 4 hills, 5 mountains, 6 cloud cap.
  final int reach;
  final Color color;
}

const _deg = math.pi / 180;

/// Where a point on the planet lands on screen.
class GlobeProjection {
  GlobeProjection({required this.size, required this.centerLon, required this.mode}) {
    switch (mode) {
      case GlobeMode.closeUp:
        tilt = 0.9;
        radius = size.height * 0.48;
        cx = size.width / 2;
        cy = size.height * 0.78 - radius * math.sin(tilt);
      case GlobeMode.whole:
        tilt = 1.25;
        radius = math.min(size.width, size.height) * 0.46;
        cx = size.width / 2;
        cy = size.height / 2;
    }
  }

  final Size size;

  /// The longitude (radians) facing the viewer.
  final double centerLon;
  final GlobeMode mode;
  late final double tilt;
  late final double radius;
  late final double cx;
  late final double cy;

  /// Projects latitude [lat] and longitude [lon] (radians). [front] is true
  /// when the point is on the visible side.
  ({Offset p, bool front, double depth}) project(double lat, double lon) {
    final d = lon - centerLon;
    final x = math.cos(lat) * math.sin(d);
    final y = math.sin(lat);
    final z = math.cos(lat) * math.cos(d);
    final y2 = y * math.cos(tilt) - z * math.sin(tilt);
    final z2 = y * math.sin(tilt) + z * math.cos(tilt);
    return (p: Offset(cx + radius * x, cy - radius * y2), front: z2 > 0, depth: z2);
  }

  /// Where harbor [slot] sits on screen (null when it faces away).
  Offset? harborAt(int slot) {
    final r = project(0, slotAngle(slot));
    return r.front ? r.p : null;
  }

  /// Where the Great Lantern sits.
  Offset get lantern => project(math.pi / 2, 0).p;

  /// The tap area of a village: at least 48 logical pixels each way.
  Rect? villageHit(int slot) {
    final p = harborAt(slot);
    if (p == null) return null;
    final s = math.max(48.0, radius * (mode == GlobeMode.closeUp ? 0.34 : 0.2));
    return Rect.fromCenter(center: p.translate(0, -s * 0.2), width: s * 1.6, height: s);
  }
}

// ── Colours ────────────────────────────────────────────────────────────────

const _sea = Color(0xFF2C6FA6);
const _seaDeep = Color(0xFF1F5686);
const _bandColors = <Band, Color>{
  Band.sunnyShore: Color(0xFFEBD9A0),
  Band.meadow: Color(0xFF8ACD52),
  Band.whisperWoods: Color(0xFF3F8A3A),
  Band.ribbonRiver: Color(0xFF5BB0E0),
  Band.ruinHills: Color(0xFFB3A56B),
  Band.echoMountains: Color(0xFF9A9A9A),
  Band.cloudCap: Color(0xFFE9EEF2),
  Band.northPeak: Color(0xFFFFE9A0),
};
const _hush = Color(0xDD6F7378);

class _Cell {
  const _Cell(this.lat, this.lon, this.band, this.row, this.col, this.sea);
  final double lat, lon;
  final Band band;
  final int row, col;
  final bool sea;
}

final _cellCache = <int, List<_Cell>>{};
const _stepDeg = 3.0;

List<_Cell> _cellsFor(Set<int> taken) {
  var key = 0;
  for (final s in taken) {
    key |= 1 << s;
  }
  return _cellCache.putIfAbsent(key, () {
    final out = <_Cell>[];
    for (var latD = 0.0; latD < 90; latD += _stepDeg) {
      for (var lonD = 0.0; lonD < 360; lonD += _stepDeg) {
        final lat = (latD + _stepDeg / 2) * _deg;
        final lon = (lonD + _stepDeg / 2) * _deg;
        final d = (90 - (latD + _stepDeg / 2)) / 90 * 124;
        final row = (kLanternRow + d * math.cos(lon)).round();
        final col = (kLanternCol + d * math.sin(lon)).round();
        out.add(_Cell(lat, lon, bandAt(row, col), row, col, isBay(row, col, taken)));
      }
    }
    return out;
  });
}

/// Paints the planet.
class GlobePainter extends CustomPainter {
  GlobePainter({
    required this.mode,
    required this.centerLon,
    required this.villages,
    required this.takenSlots,
    required this.isHushed,
    this.showTags = true,
  });

  final GlobeMode mode;
  final double centerLon;
  final List<GlobeVillage> villages;
  final Set<int> takenSlots;

  /// Whether the Hush (fog) still covers the land at this board cell. For
  /// your own slice this is your fog; for others it comes from `reach`.
  final bool Function(int row, int col, double lon) isHushed;
  final bool showTags;

  @override
  void paint(Canvas canvas, Size size) {
    final proj = GlobeProjection(size: size, centerLon: centerLon, mode: mode);
    final disc = Rect.fromCircle(center: Offset(proj.cx, proj.cy), radius: proj.radius);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // The sea fills the disc; the Deep is darker towards the rim.
    canvas.drawCircle(
      disc.center,
      proj.radius,
      Paint()
        ..shader = RadialGradient(colors: const [_sea, _seaDeep]).createShader(disc),
    );

    // Land cells, front side only.
    final paint = Paint()..isAntiAlias = false; // no seams between cells
    for (final cell in _cellsFor(takenSlots)) {
      if (cell.band == Band.deep || cell.sea) continue;
      final quad = _quad(proj, cell);
      if (quad == null) continue;
      paint.color = _bandColors[cell.band] ?? _sea;
      canvas.drawPath(quad, paint);
      if (isHushed(cell.row, cell.col, cell.lon)) {
        paint.color = _hush;
        canvas.drawPath(quad, paint);
      }
    }

    _paintRim(canvas, proj);
    _paintLantern(canvas, proj);
    _paintSeaFriends(canvas, proj);

    // Villages, back to front.
    final order = [...villages]..sort((a, b) {
        final da = proj.project(0, slotAngle(a.slot)).depth;
        final db = proj.project(0, slotAngle(b.slot)).depth;
        return da.compareTo(db);
      });
    for (final v in order) {
      final at = proj.harborAt(v.slot);
      if (at == null) continue;
      _paintVillage(canvas, proj, v, at);
    }
    canvas.restore();
  }

  Path? _quad(GlobeProjection proj, _Cell cell) {
    const h = _stepDeg / 2 * _deg;
    final corners = [
      proj.project(cell.lat - h, cell.lon - h),
      proj.project(cell.lat - h, cell.lon + h),
      proj.project(cell.lat + h, cell.lon + h),
      proj.project(cell.lat + h, cell.lon - h),
    ];
    if (corners.any((c) => !c.front)) return null;
    return Path()
      ..moveTo(corners[0].p.dx, corners[0].p.dy)
      ..lineTo(corners[1].p.dx, corners[1].p.dy)
      ..lineTo(corners[2].p.dx, corners[2].p.dy)
      ..lineTo(corners[3].p.dx, corners[3].p.dy)
      ..close();
  }

  void _paintRim(Canvas canvas, GlobeProjection proj) {
    canvas.drawCircle(
      Offset(proj.cx, proj.cy),
      proj.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = WColors.ink.withOpacity(0.55),
    );
  }

  void _paintLantern(Canvas canvas, GlobeProjection proj) {
    final top = proj.project(math.pi / 2, 0);
    if (!top.front) return;
    final c = top.p;
    final r = proj.radius * (mode == GlobeMode.closeUp ? 0.16 : 0.1);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          WColors.sun.withOpacity(mode == GlobeMode.closeUp ? 0.55 : 0.8),
          WColors.sun.withOpacity(0),
        ]).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(c, r * 0.16, Paint()..color = WColors.sun);
  }

  // Static drawings in the Deep (Inky, Gulp, Nessa): spec-18 only draws them.
  void _paintSeaFriends(Canvas canvas, GlobeProjection proj) {
    void friend(double latD, double lonD, void Function(Offset p, double s) draw) {
      final r = proj.project(latD * _deg, lonD * _deg);
      if (!r.front || r.depth < 0.12) return;
      draw(r.p, proj.radius * (mode == GlobeMode.closeUp ? 0.07 : 0.035) * (0.6 + r.depth));
    }

    friend(-24, 20, (p, s) {
      // Inky: a round head and eight little arms.
      canvas.drawCircle(p, s, Paint()..color = const Color(0xFFB07AD6));
      for (var i = 0; i < 8; i++) {
        final a = math.pi * (0.15 + 0.1 * i);
        canvas.drawLine(p.translate(math.cos(a) * s * 0.7, s * 0.6),
            p.translate(math.cos(a) * s * 1.6, s * 1.5 + math.sin(a) * s * 0.3),
            Paint()
              ..color = const Color(0xFFB07AD6)
              ..strokeWidth = math.max(1.5, s * 0.22)
              ..strokeCap = StrokeCap.round);
      }
      canvas.drawCircle(p.translate(-s * 0.3, -s * 0.1), s * 0.14, Paint()..color = WColors.white);
      canvas.drawCircle(p.translate(s * 0.3, -s * 0.1), s * 0.14, Paint()..color = WColors.white);
    });
    friend(-18, -35, (p, s) {
      // Gulp: a whale, round and cheerful.
      final body = Rect.fromCenter(center: p, width: s * 3, height: s * 1.5);
      canvas.drawOval(body, Paint()..color = const Color(0xFF6C8FC7));
      canvas.drawCircle(p.translate(s * 1.5, -s * 0.2), s * 0.5, Paint()..color = const Color(0xFF6C8FC7));
      canvas.drawCircle(p.translate(-s * 0.9, -s * 0.2), s * 0.12, Paint()..color = WColors.ink);
    });
    friend(-28, -80, (p, s) {
      // Nessa: a ribbon serpent.
      final path = Path()..moveTo(p.dx - s * 2, p.dy);
      for (var i = 1; i <= 4; i++) {
        path.quadraticBezierTo(
            p.dx - s * 2 + s * i, p.dy + (i.isOdd ? -s : s), p.dx - s * 2 + s * i + s * 0.5, p.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, s * 0.5)
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF52B788));
    });
  }

  void _paintVillage(Canvas canvas, GlobeProjection proj, GlobeVillage v, Offset at) {
    final s = proj.radius * (mode == GlobeMode.closeUp ? 0.075 : 0.036);
    final depth = proj.project(0, slotAngle(v.slot)).depth;
    final squash = (0.35 + 0.4 * depth).clamp(0.3, 0.8);
    // The plate the village stands on.
    final plate = Rect.fromCenter(center: at, width: s * 5.2, height: s * 5.2 * squash);
    canvas.drawOval(plate, Paint()..color = const Color(0xFFD9C28A));
    canvas.drawOval(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = WColors.ink.withOpacity(0.6),
    );
    // Up to four little buildings.
    final words = v.buildings.take(4).toList();
    for (var i = 0; i < words.length; i++) {
      final x = at.dx + (i - (words.length - 1) / 2) * s * 1.15;
      final y = at.dy - s * 0.2 + (i.isOdd ? s * 0.25 : 0);
      _house(canvas, Offset(x, y), s * 0.95, _wallFor(words[i]));
    }
    if (words.isEmpty) {
      _house(canvas, at.translate(0, -s * 0.2), s * 0.95, v.color);
    }
    if (showTags) _tag(canvas, v.name, at.translate(0, s * 0.9 * (squash + 0.5)), v.color);
  }

  Color _wallFor(String word) {
    const palette = [
      Color(0xFFE8A87C),
      Color(0xFFF2D16B),
      Color(0xFF9FD3C7),
      Color(0xFFE5989B),
      Color(0xFFB5C99A),
    ];
    return palette[word.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length];
  }

  void _house(Canvas canvas, Offset base, double s, Color wall) {
    final body = Rect.fromLTWH(base.dx - s * 0.5, base.dy - s * 0.8, s, s * 0.8);
    canvas.drawRect(body, Paint()..color = wall);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - s * 0.65, base.dy - s * 0.8)
        ..lineTo(base.dx, base.dy - s * 1.45)
        ..lineTo(base.dx + s * 0.65, base.dy - s * 0.8)
        ..close(),
      Paint()..color = WColors.brick,
    );
    canvas.drawRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = WColors.ink,
    );
  }

  void _tag(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'AtkinsonHyperlegible',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: WColors.ink,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: 120);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: tp.width + 16, height: tp.height + 6),
      const Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = WColors.card);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = WColors.ink,
    );
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(GlobePainter oldDelegate) =>
      oldDelegate.centerLon != centerLon ||
      oldDelegate.mode != mode ||
      oldDelegate.villages != villages ||
      oldDelegate.takenSlots != takenSlots ||
      oldDelegate.showTags != showTags;
}

/// Hush by climb: land above the band index [reach] still has the Hush.
/// [reach] counts from the shore (0 shore, 1 meadow, 2 woods ...).
bool hushedByReach(int row, int col, int reach) {
  final band = bandAt(row, col);
  final index = switch (band) {
    Band.sunnyShore => 0,
    Band.meadow => 1,
    Band.whisperWoods => 2,
    Band.ribbonRiver => 3,
    Band.ruinHills => 4,
    Band.echoMountains => 5,
    Band.cloudCap => 6,
    Band.northPeak => 7,
    Band.deep => -1,
  };
  return index > reach;
}

/// The reach number for the furthest band a village has cleared fog in.
int reachOfBand(Band band) => switch (band) {
      Band.sunnyShore => 0,
      Band.meadow => 1,
      Band.whisperWoods => 2,
      Band.ribbonRiver => 3,
      Band.ruinHills => 4,
      Band.echoMountains => 5,
      Band.cloudCap => 6,
      Band.northPeak => 7,
      Band.deep => 0,
    };

/// The band name for a reach number ("the Woods").
String reachName(int reach) {
  const names = [
    'the Shore',
    'the Meadow',
    'the Woods',
    'the River',
    'the Hills',
    'the Mountains',
    'the Cloud Cap',
    'the Peak',
  ];
  return names[reach.clamp(0, names.length - 1)];
}

/// A [GlobeView] (see globe_view.dart) turns the planet with a short ease.
double wrapLon(double lon) {
  var l = lon % (2 * math.pi);
  if (l < 0) l += 2 * math.pi;
  return l;
}

/// Shortest signed way round from [from] to [to], in radians.
double lonDelta(double from, double to) {
  var d = (to - from) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  if (d < -math.pi) d += 2 * math.pi;
  return d;
}
