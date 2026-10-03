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

const double isoBlockHeight = isoTileH * 0.45;
const double _slabHeight = 6;
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
    final anchor = groundOf(s.middle) - const Offset(0, isoBlockHeight);
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
            ? () => _paintBlock(canvas, scene.groundOf(index), letter, block, lit)
            : () => _paintSlab(canvas, scene.groundOf(index), letter, lit),
      ));
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

  void _paintBlock(Canvas canvas, Offset g, String letter, BoardStructure s, bool lit) {
    const scale = 0.94;
    final ground = _corners(g, scale, 0);
    final top = _corners(g, scale, isoBlockHeight);
    final leftFace = _poly([ground.left, ground.bottom, top.bottom, top.left]);
    final rightFace = _poly([ground.bottom, ground.right, top.right, top.bottom]);
    final topFace = _poly([top.top, top.right, top.bottom, top.left]);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lit ? 2.5 : 2
      ..strokeJoin = StrokeJoin.round
      ..color = WColors.ink;

    canvas.drawPath(leftFace, Paint()..color = _blockLeft);
    canvas.drawPath(rightFace, Paint()..color = _blockRight);
    // The building's color as a 5px stripe along the bottom of the face
    // that runs along the word.
    final stripe = s.across
        ? _poly([ground.left, ground.bottom, ground.bottom - const Offset(0, 5), ground.left - const Offset(0, 5)])
        : _poly([ground.bottom, ground.right, ground.right - const Offset(0, 5), ground.bottom - const Offset(0, 5)]);
    canvas.drawPath(stripe, Paint()..color = s.def.color);
    canvas.drawPath(topFace, Paint()..color = lit ? _highlightTop : _blockTop);
    for (final face in [leftFace, rightFace, topFace]) {
      canvas.drawPath(face, outline);
    }

    // The letter sits on that same side face, skewed to lie on it, so the
    // building above never covers it.
    final tp = _letter(letter, 19, WColors.ink);
    final faceCenter = s.across
        ? Offset((ground.left.dx + ground.bottom.dx) / 2, (ground.left.dy + ground.bottom.dy) / 2 - isoBlockHeight / 2 - 1)
        : Offset((ground.bottom.dx + ground.right.dx) / 2, (ground.bottom.dy + ground.right.dy) / 2 - isoBlockHeight / 2 - 1);
    final skew = Matrix4.identity()..setEntry(1, 0, s.across ? 0.5 : -0.5);
    canvas.save();
    canvas.translate(faceCenter.dx, faceCenter.dy);
    canvas.transform(skew.storage);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
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
    final anchor = scene.groundOf(s.middle) - const Offset(0, isoBlockHeight);
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
