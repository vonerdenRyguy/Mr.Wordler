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

/// A perspective camera over the planet: far away it sees the whole globe from
/// above; as you zoom in it comes down and tilts, so the village sits low on
/// the screen and the horizon curves across the top, like zooming into a globe
/// in a map app.
///
/// The planet is a unit sphere at the origin (north pole up). The camera
/// looks at the point ([centerLat], [centerLon]), standing south of it and
/// above it by an altitude that shrinks as [zoom] grows.
class GlobeProjection {
  GlobeProjection({
    required this.size,
    required this.centerLon,
    this.centerLat = 0.42,
    this.zoom = 1.0,
  })  : radius = math.min(size.width, size.height) * 0.46 * zoom,
        cx = size.width / 2,
        _alt = (_e0 - 1) / zoom {
    final t = (((zoom - 1.2) / 4.0).clamp(0.0, 1.0)).toDouble();
    final smooth = t * t * (3 - 2 * t);
    tilt = 0.95 * smooth;
    cy = size.height * (0.5 + 0.12 * smooth);
    focal = math.min(size.width, size.height) * 0.46 * math.sqrt(_e0 * _e0 - 1);

    final sinLat = math.sin(centerLat), cosLat = math.cos(centerLat);
    final sinLon = math.sin(centerLon), cosLon = math.cos(centerLon);
    final target = _V(cosLat * sinLon, sinLat, cosLat * cosLon);
    final north = _V(-sinLat * sinLon, cosLat, -sinLat * cosLon);
    _eye = target + (target * math.cos(tilt) - north * math.sin(tilt)) * _alt;
    final fwd = (target - _eye).unit();
    _f = fwd;
    _r = fwd.cross(north).unit();
    _u = _r.cross(fwd);
    _eyeLen = _eye.len();
  }

  static const double _e0 = 3.2;

  final Size size;

  /// The longitude and latitude (radians) the camera looks at.
  final double centerLon;
  final double centerLat;

  /// 1 shows the whole planet; higher zooms in.
  final double zoom;

  /// A size for things drawn at the planet's scale (the planet's radius in
  /// pixels when the whole of it is in view).
  final double radius;
  final double cx;
  late final double cy;
  late final double focal;
  late final double tilt;
  late final _V _eye;
  late final _V _f, _r, _u;
  late final double _eyeLen;
  final double _alt;

  /// Pixels on the screen per radian of ground at the point looked at.
  double get pixelsPerRadian => focal / _alt;

  /// Projects latitude [lat] and longitude [lon] (radians). [front] is true
  /// when the point is on the side the camera can see (and in front of it).
  ({Offset p, bool front, double depth}) project(double lat, double lon) {
    final cl = math.cos(lat);
    return _projectPoint(_V(cl * math.sin(lon), math.sin(lat), cl * math.cos(lon)));
  }

  ({Offset p, bool front, double depth}) _projectPoint(_V p) {
    final v = p - _eye;
    final z = v.dot(_f);
    final depth = p.dot(_eye) / _eyeLen; // cos of the angle from under the camera
    final front = p.dot(_eye) > 1.0 + 1e-9 && z > 0.02;
    if (z <= 1e-6) return (p: Offset(cx, cy), front: false, depth: depth);
    return (p: Offset(cx + focal * v.dot(_r) / z, cy - focal * v.dot(_u) / z), front: front, depth: depth);
  }

  /// Distance from the camera along its view direction, for a point.
  double _zOf(double lat, double lon) {
    final cl = math.cos(lat);
    return (_V(cl * math.sin(lon), math.sin(lat), cl * math.cos(lon)) - _eye).dot(_f);
  }

  /// How many pixels a stretch of [radians] of ground spans at ([lat], [lon]).
  double pixelsAt(double lat, double lon, double radians) {
    final z = _zOf(lat, lon);
    return z <= 1e-6 ? double.infinity : focal * radians / z;
  }

  /// The outline of the planet as a path (a closed circle when the whole
  /// planet is in view; the horizon with everything below it when you are
  /// close).
  Path silhouette() {
    final e = _eyeLen;
    final centre = _eye * (1 / (e * e));
    final rho = math.sqrt(math.max(0.0, 1 - 1 / (e * e)));
    final axis = _eye.unit();
    var a = axis.cross(_V(0, 1, 0));
    if (a.len() < 1e-6) a = _V(1, 0, 0);
    a = a.unit();
    final b = axis.cross(a).unit();
    final pts = <Offset>[];
    var all = true;
    for (var i = 0; i < 180; i++) {
      final th = i * 2 * math.pi / 180;
      final p = centre + (a * math.cos(th) + b * math.sin(th)) * rho;
      final r = _projectPoint(p);
      final z = (p - _eye).dot(_f);
      if (z <= 0.01) {
        all = false;
        continue;
      }
      pts.add(r.p);
    }
    if (all) return Path()..addPolygon(pts, true);
    if (pts.length < 2) return Path()..addRect(Offset.zero & size);
    // Only the part of the horizon in front of the camera: everything below it
    // is planet.
    pts.sort((p, q) => p.dx.compareTo(q.dx));
    final path = Path()..moveTo(pts.first.dx - 2000, size.height + 4000);
    path.lineTo(pts.first.dx - 2000, pts.first.dy);
    for (final p in pts) {
      path.lineTo(p.dx, p.dy);
    }
    path.lineTo(pts.last.dx + 2000, pts.last.dy);
    path.lineTo(pts.last.dx + 2000, size.height + 4000);
    path.close();
    return path;
  }

  /// Where harbor [slot] sits on screen (null when it faces away).
  Offset? harborAt(int slot) {
    final r = project(0, slotAngle(slot));
    return r.front ? r.p : null;
  }

  /// Where the Great Lantern sits.
  Offset get lantern => project(math.pi / 2, 0).p;

  /// Screen size (pixels) of one board cell at the point looked at.
  double get cellPixels => pixelsPerRadian * (math.pi / 2) / kHarborDistance;

  /// The tap area of a village: at least 48 logical pixels each way.
  Rect? villageHit(int slot) {
    final p = harborAt(slot);
    if (p == null) return null;
    final s = math.min(math.max(48.0, cellPixels * 11), size.width * 0.5);
    return Rect.fromCenter(center: p.translate(0, -s * 0.15), width: s * 1.6, height: s);
  }
}

class _V {
  const _V(this.x, this.y, this.z);
  final double x, y, z;
  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double k) => _V(x * k, y * k, z * k);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double len() => math.sqrt(x * x + y * y + z * z);
  _V unit() {
    final l = len();
    return l == 0 ? this : _V(x / l, y / l, z / l);
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
    final outline = proj.silhouette();
    final disc = outline.getBounds();
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Sky behind the planet, then the sea filling it; the Deep is darker
    // towards the rim.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFBFE6F5));
    canvas.drawPath(
      outline,
      Paint()..shader = RadialGradient(colors: const [_sea, _seaDeep]).createShader(disc),
    );

    canvas.save();
    canvas.clipPath(outline);
    _paintLand(canvas, size, proj);
    _paintSeaFriends(canvas, proj);
    _paintLantern(canvas, proj);
    canvas.restore();
    _paintShading(canvas, proj, outline, disc);

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

  // Land, drawn as lat/lon tiles that split finer the closer they are to the
  // camera (so the shore stays smooth when you zoom right in), skipping what
  // is round the back or off screen.
  void _paintLand(Canvas canvas, Size size, GlobeProjection proj) {
    final paint = Paint()..isAntiAlias = false; // no seams between cells
    final screen = Offset.zero & size;
    const root = 12 * _deg;
    const minSize = 0.2 * _deg;

    void tile(double lat, double lon, double sz, int depth) {
      final mLat = lat + sz / 2, mLon = lon + sz / 2;
      final c = proj.project(mLat, mLon);
      final z = proj._zOf(mLat, mLon);
      if (z <= 0.02) return;
      // Round the back (allowing for the tile's own size).
      if (c.depth * proj._eyeLen - 1 < -sz * 1.5 * proj._eyeLen) return;
      final px = proj.focal * sz / z;
      final pad = px * 1.5 + 8;
      if (!screen.inflate(pad).contains(c.p)) return;
      if (px > 6 && sz > minSize) {
        final h = sz / 2;
        tile(lat, lon, h, depth + 1);
        tile(lat, lon + h, h, depth + 1);
        tile(lat + h, lon, h, depth + 1);
        tile(lat + h, lon + h, h, depth + 1);
        return;
      }
      final b = sphereToBoard(mLat, mLon);
      final row = b.row.round(), col = b.col.round();
      final band = bandAt(row, col);
      if (band == Band.deep || isBay(row, col, takenSlots)) return;
      final p0 = proj.project(lat, lon);
      final p1 = proj.project(lat, lon + sz);
      final p2 = proj.project(lat + sz, lon + sz);
      final p3 = proj.project(lat + sz, lon);
      if (!p0.front || !p1.front || !p2.front || !p3.front) return;
      final quad = Path()
        ..moveTo(p0.p.dx, p0.p.dy)
        ..lineTo(p1.p.dx, p1.p.dy)
        ..lineTo(p2.p.dx, p2.p.dy)
        ..lineTo(p3.p.dx, p3.p.dy)
        ..close();
      paint.color = _bandColors[band] ?? _sea;
      canvas.drawPath(quad, paint);
      if (isHushed(row, col, mLon)) {
        paint.color = _hush;
        canvas.drawPath(quad, paint);
      }
    }

    for (var lat = -6 * _deg; lat < math.pi / 2 - 1e-9; lat += root) {
      for (var lon = 0.0; lon < 2 * math.pi - 1e-9; lon += root) {
        tile(lat, lon, root, 0);
      }
    }
  }

  // A soft shade towards the rim (the curve) and a thin atmosphere line along
  // the horizon.
  void _paintShading(Canvas canvas, GlobeProjection proj, Path outline, Rect disc) {
    canvas.save();
    canvas.clipPath(outline);
    canvas.drawRect(
      disc.inflate(10),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.35),
          radius: 1.05,
          colors: [Colors.white.withOpacity(0.10), Colors.transparent, Colors.black.withOpacity(0.38)],
          stops: const [0, 0.55, 1],
        ).createShader(disc),
    );
    canvas.restore();
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF9BD3F0).withOpacity(0.8),
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
