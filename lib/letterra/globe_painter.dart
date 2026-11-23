import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../explore/fog.dart';
import '../village/magic_word.dart';
import '../ui/tokens.dart';
import 'planet.dart';

// Letterra's globe (spec-18, canvas W234 and X252). A true sphere seen in
// orthographic projection, centred on any point: spin it to see the other
// villages, pinch (or use + / -) to zoom in until the village's own tiles
// show, still on the curved surface, like zooming into a globe in a map app.
//
// The board's top-down disc IS the planet: the Lantern is the North Pole, the
// Sunny Shore (the harbors) the equator, and harbor slot s sits at longitude
// s * 45 degrees. A board cell at distance d from the Lantern in direction
// lon sits at latitude 90 * (1 - d / 120). So fog, bands, bays and each
// village's letters all come from the same board.
//
// Art is placeholder, drawn in code.

/// One person's village as the globe draws it.
class GlobeVillage {
  const GlobeVillage({
    required this.slot,
    required this.name,
    this.buildings = const [],
    this.reach = 0,
    this.color = WColors.sun,
    this.letters = const {},
    this.buildingRuns = const [],
  });

  final int slot;
  final String name;

  /// Up to four of their building words (WELL, FARM...).
  final List<String> buildings;

  /// How far up they have climbed, as a [Band] index counted from the shore:
  /// 0 shore, 1 meadow, 2 woods, 3 river, 4 hills, 5 mountains, 6 cloud cap.
  final int reach;
  final Color color;

  /// Board cell index -> letter, for the tiles drawn when you zoom in.
  final Map<int, String> letters;

  /// The cells of each standing building, for colouring those tiles.
  final List<({String word, List<int> cells})> buildingRuns;
}

const _deg = math.pi / 180;

/// Highest zoom (1 = the whole planet fits the box).
const double kGlobeMaxZoom = 7.0;
const double kGlobeMinZoom = 1.0;

/// Latitude / longitude (radians) of a board position (fractional allowed).
({double lat, double lon}) boardToSphere(double row, double col) {
  final dr = row - kLanternRow, dc = col - kLanternCol;
  final d = math.sqrt(dr * dr + dc * dc);
  final lon = d == 0 ? 0.0 : math.atan2(dc, dr);
  final lat = (math.pi / 2) * (1 - d / kHarborDistance);
  return (lat: lat.clamp(-math.pi / 2, math.pi / 2).toDouble(), lon: lon);
}

/// The board position of a latitude / longitude (radians).
({double row, double col}) sphereToBoard(double lat, double lon) {
  final d = (1 - lat / (math.pi / 2)) * kHarborDistance;
  return (row: kLanternRow + d * math.cos(lon), col: kLanternCol + d * math.sin(lon));
}

/// Where a point on the planet lands on screen.
class GlobeProjection {
  GlobeProjection({
    required this.size,
    required this.centerLon,
    this.centerLat = 0.42,
    this.zoom = 1.0,
  })  : radius = math.min(size.width, size.height) * 0.46 * zoom,
        cx = size.width / 2,
        cy = size.height / 2,
        _sinLat0 = math.sin(centerLat),
        _cosLat0 = math.cos(centerLat);

  final Size size;

  /// The longitude and latitude (radians) at the middle of the screen.
  final double centerLon;
  final double centerLat;

  /// 1 shows the whole planet; higher zooms in.
  final double zoom;
  final double radius;
  final double cx;
  final double cy;
  final double _sinLat0;
  final double _cosLat0;

  /// Projects latitude [lat] and longitude [lon] (radians). [front] is true
  /// when the point is on the visible side.
  ({Offset p, bool front, double depth}) project(double lat, double lon) {
    final dl = lon - centerLon;
    final cosLat = math.cos(lat), sinLat = math.sin(lat);
    final cosD = math.cos(dl);
    final x = cosLat * math.sin(dl);
    final y = _cosLat0 * sinLat - _sinLat0 * cosLat * cosD;
    final z = _sinLat0 * sinLat + _cosLat0 * cosLat * cosD;
    return (p: Offset(cx + radius * x, cy - radius * y), front: z > 0, depth: z);
  }

  /// Where harbor [slot] sits on screen (null when it faces away).
  Offset? harborAt(int slot) {
    final r = project(0, slotAngle(slot));
    return r.front ? r.p : null;
  }

  /// Where the Great Lantern sits.
  Offset get lantern => project(math.pi / 2, 0).p;

  /// Screen size (pixels) of one board cell at the harbor.
  double get cellPixels => radius * (math.pi / 2) / kHarborDistance;

  /// The tap area of a village: at least 48 logical pixels each way.
  Rect? villageHit(int slot) {
    final p = harborAt(slot);
    if (p == null) return null;
    final s = math.min(math.max(48.0, radius * 0.22), size.width * 0.5);
    return Rect.fromCenter(center: p.translate(0, -s * 0.15), width: s * 1.6, height: s);
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
const _tile = Color(0xFFE9D9B5);

/// Paints the planet.
class GlobePainter extends CustomPainter {
  GlobePainter({
    required this.centerLon,
    required this.centerLat,
    required this.zoom,
    required this.villages,
    required this.takenSlots,
    required this.isHushed,
    this.showTags = true,
  });

  final double centerLon;
  final double centerLat;
  final double zoom;
  final List<GlobeVillage> villages;
  final Set<int> takenSlots;

  /// Whether the Hush (fog) still covers the land at this board cell. For
  /// your own slice this is your fog; for others it comes from `reach`.
  final bool Function(int row, int col, double lon) isHushed;
  final bool showTags;

  @override
  void paint(Canvas canvas, Size size) {
    final proj = GlobeProjection(size: size, centerLon: centerLon, centerLat: centerLat, zoom: zoom);
    final disc = Rect.fromCircle(center: Offset(proj.cx, proj.cy), radius: proj.radius);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // The sea fills the disc; the Deep is darker towards the rim.
    canvas.drawCircle(
      disc.center,
      proj.radius,
      Paint()..shader = RadialGradient(colors: const [_sea, _seaDeep]).createShader(disc),
    );

    _paintLand(canvas, size, proj);
    _paintSeaFriends(canvas, proj);
    _paintLantern(canvas, proj);
    _paintShading(canvas, proj, disc);

    // Villages, back to front.
    final order = [...villages]..sort((a, b) {
        final da = proj.project(0, slotAngle(a.slot)).depth;
        final db = proj.project(0, slotAngle(b.slot)).depth;
        return da.compareTo(db);
      });
    for (final v in order) {
      final at = proj.harborAt(v.slot);
      if (at == null) continue;
      _paintVillage(canvas, size, proj, v, at);
    }
    canvas.restore();
  }

  // Land cells on the visible side, sampled finer the closer you are, and
  // only over the part of the globe that is on screen.
  void _paintLand(Canvas canvas, Size size, GlobeProjection proj) {
    final stepDeg = ((6 / proj.radius) / _deg).clamp(0.3, 3.0);
    final step = stepDeg * _deg;
    final halfDiag = math.sqrt(size.width * size.width + size.height * size.height) / 2;
    final reach = math.asin(math.min(1.0, halfDiag / proj.radius)) + step * 2;
    final latMin = math.max(-4 * _deg, centerLat - reach);
    final latMax = math.min(math.pi / 2, centerLat + reach);
    if (latMax <= latMin) return;
    final polar = latMax > 85 * _deg || reach > 1.25;
    final worstLat = math.max(latMin.abs(), latMax.abs()).clamp(0.0, 1.5);
    final span = polar ? math.pi : math.min(math.pi, reach / math.cos(worstLat));

    final paint = Paint()..isAntiAlias = false; // no seams between cells
    final lat0 = (latMin / step).floor() * step;
    final lon0 = ((centerLon - span) / step).floor() * step;
    final nLon = (2 * span / step).ceil() + 1;
    for (var lat = lat0; lat < latMax; lat += step) {
      final midLat = lat + step / 2;
      for (var k = 0; k < nLon; k++) {
        final lon = lon0 + k * step;
        final midLon = lon + step / 2;
        final b = sphereToBoard(midLat, midLon);
        final row = b.row.round(), col = b.col.round();
        final band = bandAt(row, col);
        if (band == Band.deep || isBay(row, col, takenSlots)) continue;
        final a = proj.project(lat, lon);
        if (!a.front) continue;
        final bb = proj.project(lat, lon + step);
        final c = proj.project(lat + step, lon + step);
        final d = proj.project(lat + step, lon);
        if (!bb.front || !c.front || !d.front) continue;
        final quad = Path()
          ..moveTo(a.p.dx, a.p.dy)
          ..lineTo(bb.p.dx, bb.p.dy)
          ..lineTo(c.p.dx, c.p.dy)
          ..lineTo(d.p.dx, d.p.dy)
          ..close();
        paint.color = _bandColors[band] ?? _sea;
        canvas.drawPath(quad, paint);
        if (isHushed(row, col, midLon)) {
          paint.color = _hush;
          canvas.drawPath(quad, paint);
        }
      }
    }
  }

  // A soft shade towards the rim (the curve) and a thin atmosphere line.
  void _paintShading(Canvas canvas, GlobeProjection proj, Rect disc) {
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    canvas.drawRect(
      disc,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.35),
          radius: 1.05,
          colors: [Colors.white.withOpacity(0.10), Colors.transparent, Colors.black.withOpacity(0.38)],
          stops: const [0, 0.55, 1],
        ).createShader(disc),
    );
    canvas.restore();
    canvas.drawCircle(
      disc.center,
      proj.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF9BD3F0).withOpacity(0.7),
    );
    canvas.drawCircle(
      disc.center,
      proj.radius + 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = WColors.ink.withOpacity(0.45),
    );
  }

  void _paintLantern(Canvas canvas, GlobeProjection proj) {
    final top = proj.project(math.pi / 2, 0);
    if (!top.front) return;
    final c = top.p;
    final r = math.min(proj.radius * 0.12, 90.0);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          WColors.sun.withOpacity(0.75),
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
      draw(r.p, math.min(proj.radius * 0.035, 60.0) * (0.6 + r.depth));
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

  void _paintVillage(Canvas canvas, Size size, GlobeProjection proj, GlobeVillage v, Offset at) {
    final cell = proj.cellPixels;
    if (cell >= 5 && v.letters.isNotEmpty) {
      _paintTiles(canvas, proj, v, cell);
      if (showTags) _tag(canvas, v.name, _tagSpot(proj, v, at), v.color);
      return;
    }
    final s = math.min(proj.radius * 0.075, 70.0);
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

  Offset _tagSpot(GlobeProjection proj, GlobeVillage v, Offset at) {
    // Just above the highest tile that is on screen, else beside the harbor.
    var top = at.dy;
    for (final i in v.letters.keys) {
      final p = _centerOf(proj, i ~/ kPlanetBoard, i % kPlanetBoard);
      if (p != null && p.dy < top) top = p.dy;
    }
    return Offset(at.dx, top - proj.cellPixels * 1.2 - 14);
  }

  Offset? _centerOf(GlobeProjection proj, int row, int col) {
    final s = boardToSphere(row + 0.5, col + 0.5);
    final r = proj.project(s.lat, s.lon);
    return r.front ? r.p : null;
  }

  // The village's own tiles on the curved surface: each board cell is a
  // quad whose corners follow the sphere, so tiles shrink and slant towards
  // the rim.
  void _paintTiles(Canvas canvas, GlobeProjection proj, GlobeVillage v, double cell) {
    final colors = <int, Color>{};
    final roofs = <Offset>[];
    for (final run in v.buildingRuns) {
      final wall = _wallFor(run.word);
      for (final c in run.cells) {
        colors[c] = wall;
      }
      final mid = run.cells[run.cells.length ~/ 2];
      final p = _centerOf(proj, mid ~/ kPlanetBoard, mid % kPlanetBoard);
      if (p != null) roofs.add(p);
    }
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell >= 12 ? 1.6 : 1
      ..color = WColors.ink.withOpacity(0.85);
    final entries = v.letters.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    for (final e in entries) {
      final row = e.key ~/ kPlanetBoard, col = e.key % kPlanetBoard;
      final pts = <Offset>[];
      var ok = true;
      for (final corner in const [(0, 0), (0, 1), (1, 1), (1, 0)]) {
        final s = boardToSphere(row + corner.$1.toDouble(), col + corner.$2.toDouble());
        final r = proj.project(s.lat, s.lon);
        if (!r.front) {
          ok = false;
          break;
        }
        pts.add(r.p);
      }
      if (!ok) continue;
      final quad = Path()..addPolygon(pts, true);
      fill.color = colors[e.key] ?? _tile;
      canvas.drawPath(quad, fill);
      canvas.drawPath(quad, edge);
      if (cell >= 13) {
        final c = Offset(
          (pts[0].dx + pts[1].dx + pts[2].dx + pts[3].dx) / 4,
          (pts[0].dy + pts[1].dy + pts[2].dy + pts[3].dy) / 4,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: e.value,
            style: TextStyle(
              fontFamily: 'LilitaOne',
              fontSize: cell * 0.62,
              color: WColors.ink,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }
    if (cell >= 7) {
      for (final p in roofs) {
        _house(canvas, p.translate(0, -cell * 0.35), cell * 1.1, Colors.transparent, bodyless: true);
      }
    }
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

  void _house(Canvas canvas, Offset base, double s, Color wall, {bool bodyless = false}) {
    final body = Rect.fromLTWH(base.dx - s * 0.5, base.dy - s * 0.8, s, s * 0.8);
    if (!bodyless) canvas.drawRect(body, Paint()..color = wall);
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - s * 0.65, base.dy - s * 0.8)
        ..lineTo(base.dx, base.dy - s * 1.45)
        ..lineTo(base.dx + s * 0.65, base.dy - s * 0.8)
        ..close(),
      Paint()..color = WColors.brick,
    );
    if (!bodyless) {
      canvas.drawRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = WColors.ink,
      );
    }
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
      oldDelegate.centerLat != centerLat ||
      oldDelegate.zoom != zoom ||
      oldDelegate.villages != villages ||
      oldDelegate.takenSlots != takenSlots ||
      oldDelegate.showTags != showTags;
}

/// The magic-word runs on a board, for colouring a village's building tiles
/// on the globe. Only exact runs (a whole across or down line) count.
List<({String word, List<int> cells})> magicRunsOn(Map<int, String> letters) {
  final out = <({String word, List<int> cells})>[];
  final words = [for (final m in kMagicWords) m.word];
  void scan(bool across) {
    final keys = letters.keys.toList()..sort();
    final seen = <int>{};
    for (final k in keys) {
      if (seen.contains(k)) continue;
      final step = across ? 1 : kPlanetBoard;
      final before = k - step;
      final startsRun = !letters.containsKey(before) ||
          (across && k % kPlanetBoard == 0) ||
          (!across && before < 0);
      if (!startsRun) continue;
      final cells = <int>[];
      var i = k;
      while (letters.containsKey(i)) {
        cells.add(i);
        seen.add(i);
        if (across && (i + 1) % kPlanetBoard == 0) break;
        i += step;
      }
      final word = cells.map((c) => letters[c]!).join();
      if (cells.length > 1 && words.contains(word)) out.add((word: word, cells: cells));
    }
  }

  scan(true);
  scan(false);
  return out;
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

/// How far up the planet a village has climbed, worked out from its fog: the
/// furthest band with a cleared cell along the straight way from the harbor
/// to the Great Lantern.
int reachFromFog(FogMap fog, int slot) {
  final h = harborCell(slot);
  final hr = h ~/ kPlanetBoard, hc = h % kPlanetBoard;
  var reach = 0;
  const steps = 120;
  for (var i = 0; i <= steps; i++) {
    final r = (hr + (kLanternRow - hr) * i / steps).round();
    final c = (hc + (kLanternCol - hc) * i / steps).round();
    if (fog.isCleared(r * kPlanetBoard + c)) {
      final v = reachOfBand(bandAt(r, c));
      if (v > reach) reach = v;
    }
  }
  return reach;
}
