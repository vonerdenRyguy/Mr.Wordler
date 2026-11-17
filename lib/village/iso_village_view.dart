import 'dart:math';

import 'package:flutter/material.dart';

import '../game/grid_board_widget.dart' show axisAlignedBoundingBox;
import '../ui/tokens.dart';
import 'iso_math.dart';
import 'structures.dart';
import 'village_art.dart';

// The angled Village view: every word on the board, on the same squares it
// uses in Words view. Magic words are raised letter blocks with their
// building standing on top; every other letter is a flat stone path slab.

/// How far above the ground a building's sprite stands. Since spec-13 it
/// stands right on the ground (it used to sit on raised letter blocks).
const double isoBuildingLift = 0;
const double _slabHeight = 6;
const double _stoneHeight = 5;
// PNGs are 3x kit units and a kit block is 80 units wide; 0.72 keeps a
// building mostly over its own word.
const double isoSpriteScale = (isoTileW / 80) * 0.72 / 3;

const _grassA = Color(0xFF8ACD52);
const _grassB = Color(0xFF80C64A);
const _blockTop = Color(0xFFF6EAD2);
const _blockLeft = Color(0xFFF3E4C5);
const _blockRight = Color(0xFFB7A88F);
const _highlightTop = Color(0xFFFFF3C4);
const _slabTop = Color(0xFFD9CBB0);
const _slabOutline = Color(0xFF6B5A48);
const _slabLeft = Color(0xFFA8987C);
const _slabRight = Color(0xFF8F8068);
const _slabLetter = Color(0xFF4A3A2C);
const _lotDirt = Color(0xFFD9C49C);
const _lotEdge = Color(0x88B89F72);
const _lotPebble = Color(0xFFB9A27A);
const _tuftColor = Color(0xFF5E9E3A);
const _flowers = [Color(0xFFF59C86), Color(0xFFFFF6E0), Color(0xFFF6C443)];
const _landmarkFill = Color(0xFFFDF1D6);
const _landmarkOutline = Color(0xFFB7791F);

/// Everything the Village view draws, worked out from the board: pure, so
/// painting and tapping agree and both can be tested.
class VillageScene {
  VillageScene({
    required this.grid,
    required this.boardCells,
    required this.structures,
    required this.landmarkIndices,
    this.spriteMeta = const {},
  }) {
    for (int i = 0; i < boardCells.length; i++) {
      if (boardCells[i] != null) occupied.add(i);
    }
    for (final s in structures) {
      for (final p in s.ordered) {
        blockOf.putIfAbsent(p, () => s);
      }
    }
  }

  final IsoGrid grid;
  final List<String?> boardCells;
  final List<BoardStructure> structures;
  final Set<int> landmarkIndices;
  final Map<String, SpriteMeta> spriteMeta;

  /// Board indices holding a letter.
  final List<int> occupied = [];

  /// Cell -> the (first) building whose word uses it. Those cells are
  /// blocks; every other letter is a slab.
  final Map<int, BoardStructure> blockOf = {};

  int rowOf(int index) => index ~/ grid.boardWidth;
  int colOf(int index) => index % grid.boardWidth;
  Offset groundOf(int index) => grid.ground(rowOf(index), colOf(index));

  /// Where [s]'s sprite is drawn, in content coordinates, or null if its
  /// art isn't known.
  Rect? buildingRect(BoardStructure s) {
    final meta = spriteMeta[s.def.word];
    if (meta == null) return null;
    final anchor = groundOf(s.middle) - const Offset(0, isoBuildingLift);
    final w = meta.width * isoSpriteScale;
    final h = meta.height * isoSpriteScale;
    // Down words draw the sprite mirrored around its anchor.
    final left = s.across ? anchor.dx - meta.anchorX * isoSpriteScale : anchor.dx - (meta.width - meta.anchorX) * isoSpriteScale;
    return Rect.fromLTWH(left, anchor.dy - meta.anchorY * isoSpriteScale, w, h);
  }

  /// The sprite pixel under content point [p] for building [s] (accounting
  /// for mirroring), for alpha hit testing.
  ({int x, int y})? spritePixelAt(BoardStructure s, Offset p) {
    final rect = buildingRect(s);
    final meta = spriteMeta[s.def.word];
    if (rect == null || meta == null || !rect.contains(p)) return null;
    var x = (p.dx - rect.left) / isoSpriteScale;
    final y = (p.dy - rect.top) / isoSpriteScale;
    if (!s.across) x = meta.width - x;
    return (x: x.floor(), y: y.floor());
  }

  /// Depth for back-to-front drawing: r + c, then c.
  double depthOf(int index) => (rowOf(index) + colOf(index)) * 100000.0 + colOf(index);

  /// A building draws just after the front-most cell of its footprint.
  double buildingDepth(BoardStructure s) => s.ordered.map(depthOf).reduce(max) + 0.5;

  /// Center of all letters (or the board center if empty), as a cell.
  ({int r, int c}) lettersCenter() {
    if (occupied.isEmpty) return (r: grid.boardHeight ~/ 2, c: grid.boardWidth ~/ 2);
    var rs = 0, cs = 0;
    for (final i in occupied) {
      rs += rowOf(i);
      cs += colOf(i);
    }
    return (r: (rs / occupied.length).round(), c: (cs / occupied.length).round());
  }
}

/// The angled village map. Pan/zoom like Words view; [onTapContent] gets
/// taps in content coordinates (null = not tappable).
class IsoVillageView extends StatefulWidget {
  const IsoVillageView({
    super.key,
    required this.scene,
    this.transformController,
    this.minScale = 0.2,
    this.maxScale = 2.5,
    this.boundaryMargin = const EdgeInsets.all(400),
    this.highlight = const {},
    this.highlightBuilding,
    this.onTapContent,
    this.interactive = true,
  });

  final VillageScene scene;
  final TransformationController? transformController;
  final double minScale;
  final double maxScale;
  final EdgeInsets boundaryMargin;
  // Cells of the word whose card is open.
  final Set<int> highlight;
  final BoardStructure? highlightBuilding;
  final ValueChanged<Offset>? onTapContent;
  // False for Home's preview: a still picture.
  final bool interactive;

  @override
  State<IsoVillageView> createState() => _IsoVillageViewState();
}

class _IsoVillageViewState extends State<IsoVillageView> {
  VillageArt? _art;
  late final TransformationController _ownController = TransformationController();

  TransformationController get _controller => widget.transformController ?? _ownController;

  @override
  void initState() {
    super.initState();
    VillageArt.load().then((art) {
      if (mounted) setState(() => _art = art);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _ownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.scene.grid.contentSize;
    return InteractiveViewer.builder(
      transformationController: _controller,
      boundaryMargin: widget.boundaryMargin,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      panEnabled: widget.interactive,
      scaleEnabled: widget.interactive,
      builder: (context, viewport) {
        final visible = axisAlignedBoundingBox(viewport);
        final painter = IsoVillagePainter(
          scene: widget.scene,
          visible: visible,
          zoom: transformScale(_controller.value),
          art: _art,
          highlight: widget.highlight,
          highlightBuilding: widget.highlightBuilding,
        );
        final paint = SizedBox(width: size.width, height: size.height, child: CustomPaint(painter: painter));
        if (widget.onTapContent == null) return paint;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => widget.onTapContent!(details.localPosition),
          child: paint,
        );
      },
    );
  }
}

class IsoVillagePainter extends CustomPainter {
  IsoVillagePainter({
    required this.scene,
    required this.visible,
    required this.zoom,
    required this.art,
    required this.highlight,
    required this.highlightBuilding,
  });

  final VillageScene scene;
  final Rect visible;
  final double zoom;
  final VillageArt? art;
  final Set<int> highlight;
  final BoardStructure? highlightBuilding;

  // One TextPainter per letter per style, shared across frames.
  static final Map<String, TextPainter> _letterCache = {};

  static TextPainter _letter(String letter, double size, Color color) {
    return _letterCache.putIfAbsent('$letter|$size|${color.value}', () {
      return TextPainter(
        text: TextSpan(
          text: letter,
          style: TextStyle(fontFamily: WFonts.display, fontSize: size, color: color, height: 1.0),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
    });
  }

  IsoGrid get grid => scene.grid;

  Path _diamond(Offset c, double scale) {
    final hw = isoTileW / 2 * scale, hh = isoTileH / 2 * scale;
    return Path()
      ..moveTo(c.dx, c.dy - hh)
      ..lineTo(c.dx + hw, c.dy)
      ..lineTo(c.dx, c.dy + hh)
      ..lineTo(c.dx - hw, c.dy)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Cells that can show anywhere in the visible area, with 2 cells of
    // margin, plus 3 rows toward the back for tall buildings.
    final area = visible.inflate(isoTileW * 2);
    final corners = [area.topLeft, area.topRight, area.bottomLeft, area.bottomRight].map(grid.cellAtExact).toList();
    final rMin = (corners.map((p) => p.r).reduce(min).floor() - 3).clamp(0, grid.boardHeight - 1);
    final rMax = corners.map((p) => p.r).reduce(max).ceil().clamp(0, grid.boardHeight - 1);
    final cMin = (corners.map((p) => p.c).reduce(min).floor() - 3).clamp(0, grid.boardWidth - 1);
    final cMax = corners.map((p) => p.c).reduce(max).ceil().clamp(0, grid.boardWidth - 1);

    _paintGrass(canvas, area, rMin, rMax, cMin, cMax);

    bool inView(int index) {
      final r = scene.rowOf(index), c = scene.colOf(index);
      return r >= rMin && r <= rMax && c >= cMin && c <= cMax && area.contains(scene.groundOf(index));
    }

    // Everything standing on the grass, back to front.
    final items = <(double, void Function())>[];
    for (final index in scene.landmarkIndices) {
      if (scene.boardCells[index] == null && inView(index)) {
        items.add((scene.depthOf(index), () => _paintLandmark(canvas, scene.groundOf(index))));
      }
    }
    for (final index in scene.occupied) {
      if (!inView(index)) continue;
      final block = scene.blockOf[index];
      final letter = scene.boardCells[index]!;
      final lit = highlight.contains(index);
      items.add((
        scene.depthOf(index),
        block != null
            ? () => _paintLot(canvas, index, scene.groundOf(index), block, lit)
            : () => _paintSlab(canvas, scene.groundOf(index), letter, lit),
      ));
      // A building's letters go on stepping-stones in front of it.
      if (block != null) {
        items.add((
          max(scene.depthOf(index), scene.buildingDepth(block)) + 0.25,
          () => _paintStone(canvas, scene.groundOf(index), letter, block, lit),
        ));
      }
    }
    final loaded = art;
    if (loaded != null) {
      for (final s in scene.structures) {
        final sprite = loaded.sprites[s.def.word];
        final rect = scene.buildingRect(s);
        if (sprite == null || rect == null || !rect.overlaps(area)) continue;
        items.add((scene.buildingDepth(s), () => _paintBuilding(canvas, s, sprite, rect)));
      }
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final item in items) {
      item.$2();
    }
  }

  void _paintGrass(Canvas canvas, Rect area, int rMin, int rMax, int cMin, int cMax) {
    // The board's whole diamond in light grass, then the alternate cells
    // as one path in the darker green. Far zoomed out, just the flat fill.
    final boardShape = Path()
      ..moveTo(grid.ground(0, 0).dx, grid.ground(0, 0).dy - isoTileH / 2)
      ..lineTo(grid.ground(0, grid.boardWidth - 1).dx + isoTileW / 2, grid.ground(0, grid.boardWidth - 1).dy)
      ..lineTo(grid.ground(grid.boardHeight - 1, grid.boardWidth - 1).dx,
          grid.ground(grid.boardHeight - 1, grid.boardWidth - 1).dy + isoTileH / 2)
      ..lineTo(grid.ground(grid.boardHeight - 1, 0).dx - isoTileW / 2, grid.ground(grid.boardHeight - 1, 0).dy)
      ..close();
    canvas.drawPath(boardShape, Paint()..color = _grassA);
    if (zoom < 0.45) return;
    final checker = Path();
    for (int r = rMin; r <= rMax; r++) {
      for (int c = cMin + ((r + cMin) % 2 == 0 ? 1 : 0); c <= cMax; c += 2) {
        final g = grid.ground(r, c);
        if (!area.contains(g)) continue;
        checker.addPath(_diamond(g, 1), Offset.zero);
      }
    }
    canvas.drawPath(checker, Paint()..color = _grassB);
  }

  void _paintLandmark(Canvas canvas, Offset g) {
    final shape = _diamond(g, 0.85);
    canvas.drawPath(shape, Paint()..color = _landmarkFill);
    canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _landmarkOutline);
    final star = _starPath(g - const Offset(0, 14 + 10), 11, 5);
    canvas.drawPath(star, Paint()..color = WColors.sun);
    canvas.drawPath(
        star,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = WColors.ink);
  }

  Path _starPath(Offset c, double outer, double inner) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -pi / 2 + i * pi / 5;
      final p = c + Offset(cos(angle) * radius, sin(angle) * radius);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  // The four corners of a cell's diamond at [scale], lifted by [lift].
  ({Offset top, Offset right, Offset bottom, Offset left}) _corners(Offset g, double scale, double lift) {
    final hw = isoTileW / 2 * scale, hh = isoTileH / 2 * scale;
    final c = g - Offset(0, lift);
    return (
      top: c - Offset(0, hh),
      right: c + Offset(hw, 0),
      bottom: c + Offset(0, hh),
      left: c - Offset(hw, 0),
    );
  }

  Path _poly(List<Offset> points) => Path()..addPolygon(points, true);

  /// A building's cell (spec-13): packed earth flush with the grass, with a
  /// soft edge and a few grass tufts and flowers where it meets the lawn.
  /// The letter goes on a stepping-stone in front (see [_paintStone]).
  void _paintLot(Canvas canvas, int index, Offset g, BoardStructure s, bool lit) {
    canvas.drawPath(
      _diamond(g, 1.08),
      Paint()
        ..color = _lotEdge
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(_diamond(g, 1.0), Paint()..color = lit ? _highlightTop : _lotDirt);
    // A couple of pebbles, always in the same places for a cell.
    final rnd = Random(index);
    for (int i = 0; i < 2; i++) {
      final p = g + Offset((rnd.nextDouble() - 0.5) * isoTileW * 0.5, (rnd.nextDouble() - 0.5) * isoTileH * 0.4);
      canvas.drawOval(Rect.fromCenter(center: p, width: 5, height: 3), Paint()..color = _lotPebble);
    }
    // Tufts on the edges that meet grass (not the rest of this lot).
    final r = scene.rowOf(index), c = scene.colOf(index);
    const hw = isoTileW / 2, hh = isoTileH / 2;
    final edges = [
      (r, c - 1, g + Offset(-hw / 2, -hh / 2)), // top-left
      (r - 1, c, g + Offset(hw / 2, -hh / 2)), // top-right
      (r, c + 1, g + Offset(hw / 2, hh / 2)), // bottom-right
      (r + 1, c, g + Offset(-hw / 2, hh / 2)), // bottom-left
    ];
    for (final (nr, nc, mid) in edges) {
      if (nr < 0 || nc < 0 || nr >= grid.boardHeight || nc >= grid.boardWidth) continue;
      final n = nr * grid.boardWidth + nc;
      if (identical(scene.blockOf[n], s) || scene.boardCells[n] != null) continue;
      if (rnd.nextDouble() < 0.35) continue;
      final along = (rnd.nextDouble() - 0.5) * 0.5;
      final p = mid + Offset(along * hw, (nr == r ? -along : along) * hh);
      _tuft(canvas, p);
      if (rnd.nextDouble() < 0.4) {
        canvas.drawCircle(p + const Offset(5, -2), 2.6, Paint()..color = _flowers[rnd.nextInt(_flowers.length)]);
      }
    }
  }

  void _tuft(Canvas canvas, Offset p) {
    final paint = Paint()
      ..color = _tuftColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p, p + const Offset(-3, -6), paint);
    canvas.drawLine(p, p + const Offset(0, -8), paint);
    canvas.drawLine(p, p + const Offset(3, -6), paint);
  }

  /// A word's letter on a small stepping-stone at the front of its lot,
  /// drawn after the building so it always stays readable.
  void _paintStone(Canvas canvas, Offset g, String letter, BoardStructure s, bool lit) {
    final ground = _corners(g, 1, 0);
    // The edge facing the viewer along the word, and a little in from it.
    final front = s.across ? (ground.left + ground.bottom) / 2 : (ground.bottom + ground.right) / 2;
    final c = Offset.lerp(g, front, 1.12)!;
    const scale = 0.4;
    final base = _corners(c, scale, 0);
    final top = _corners(c, scale, _stoneHeight);
    canvas.drawOval(Rect.fromCenter(center: c + const Offset(0, 2), width: isoTileW * 0.44, height: isoTileH * 0.36),
        Paint()..color = const Color(0x333B2A1E));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..color = WColors.ink;
    final leftFace = _poly([base.left, base.bottom, top.bottom, top.left]);
    final rightFace = _poly([base.bottom, base.right, top.right, top.bottom]);
    final topFace = _poly([top.top, top.right, top.bottom, top.left]);
    canvas.drawPath(leftFace, Paint()..color = _blockLeft);
    canvas.drawPath(rightFace, Paint()..color = _blockRight);
    canvas.drawPath(topFace, Paint()..color = lit ? _highlightTop : _blockTop);
    for (final f in [leftFace, rightFace, topFace]) {
      canvas.drawPath(f, edge);
    }
    // The building's color as a thin line under the stone's front.
    canvas.drawLine(base.left + const Offset(2, 0), base.bottom, Paint()
      ..color = s.def.color
      ..strokeWidth = 2.5);
    canvas.drawLine(base.bottom, base.right - const Offset(2, 0), Paint()
      ..color = s.def.color
      ..strokeWidth = 2.5);
    final tp = _letter(letter, 15, WColors.ink);
    tp.paint(canvas, c - const Offset(0, _stoneHeight) - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintSlab(Canvas canvas, Offset g, String letter, bool lit) {
    const scale = 0.9;
    final ground = _corners(g, scale, 0);
    final top = _corners(g, scale, _slabHeight);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = WColors.ink;
    final leftFace = _poly([ground.left, ground.bottom, top.bottom, top.left]);
    final rightFace = _poly([ground.bottom, ground.right, top.right, top.bottom]);
    canvas.drawPath(leftFace, Paint()..color = _slabLeft);
    canvas.drawPath(rightFace, Paint()..color = _slabRight);
    canvas.drawPath(leftFace, edge);
    canvas.drawPath(rightFace, edge);
    final topFace = _poly([top.top, top.right, top.bottom, top.left]);
    canvas.drawPath(topFace, Paint()..color = lit ? _highlightTop : _slabTop);
    canvas.drawPath(
        topFace,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lit ? 2.5 : 1.5
          ..color = lit ? WColors.ink : _slabOutline);
    final tp = _letter(letter, 21, _slabLetter);
    final center = g - const Offset(0, _slabHeight);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintBuilding(Canvas canvas, BoardStructure s, BuildingSprite sprite, Rect rect) {
    if (identical(s, highlightBuilding)) {
      canvas.drawCircle(
        rect.center,
        max(rect.width, rect.height) * 0.55,
        Paint()
          ..color = WColors.sun.withOpacity(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
      );
    }
    final anchor = scene.groundOf(s.middle) - const Offset(0, isoBuildingLift);
    // A soft contact shadow on the ground, so it stands there.
    canvas.drawOval(
      Rect.fromCenter(center: anchor + const Offset(0, 4), width: rect.width * 0.7, height: isoTileH * 0.8),
      Paint()
        ..color = const Color(0x553B2A1E)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    if (!s.across) canvas.scale(-1, 1);
    canvas.scale(isoSpriteScale);
    canvas.drawImage(
      sprite.image,
      Offset(-sprite.meta.anchorX, -sprite.meta.anchorY),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(IsoVillagePainter oldDelegate) =>
      oldDelegate.visible != visible ||
      oldDelegate.zoom != zoom ||
      !identical(oldDelegate.scene, scene) ||
      !identical(oldDelegate.art, art) ||
      oldDelegate.highlight != highlight ||
      !identical(oldDelegate.highlightBuilding, highlightBuilding);
}

/// What a tap in Village view landed on.
sealed class VillageHit {
  const VillageHit();
}

class BuildingHit extends VillageHit {
  const BuildingHit(this.structure);
  final BoardStructure structure;
}

class CellHit extends VillageHit {
  const CellHit(this.index);
  final int index;
}

class NoHit extends VillageHit {
  const NoHit();
}

/// Buildings first, front to back, using the sprite's alpha ([opaque]
/// answers "is this sprite pixel solid?"; null treats every pixel inside
/// the sprite's rectangle as solid). Otherwise the letter under the tap,
/// trying the point itself and then the point shifted down by a slab's
/// height, so the top of a raised slab or stone hits its own cell.
VillageHit hitTestVillage(
  Offset p,
  VillageScene scene, {
  bool Function(BoardStructure s, int x, int y)? opaque,
}) {
  final front = [...scene.structures]..sort((a, b) => scene.buildingDepth(b).compareTo(scene.buildingDepth(a)));
  for (final s in front) {
    final pixel = scene.spritePixelAt(s, p);
    if (pixel == null) continue;
    if (opaque == null || opaque(s, pixel.x, pixel.y)) return BuildingHit(s);
  }
  for (final point in [p, p + const Offset(0, _slabHeight)]) {
    final cell = scene.grid.cellAt(point);
    if (cell == null) continue;
    final index = cell.r * scene.grid.boardWidth + cell.c;
    if (scene.boardCells[index] != null) return CellHit(index);
  }
  return const NoHit();
}
