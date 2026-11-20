import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../explore/fog.dart';
import '../explore/island_map.dart';
import '../game/grid_board_widget.dart' show axisAlignedBoundingBox;
import '../ui/tokens.dart';
import '../villagers/villager_look.dart';
import '../villagers/walkers.dart';
import 'building_art.dart';
import 'iso_math.dart';
import 'structures.dart';
import 'village_art.dart';

// The angled Village view: every word on the board, on the same squares it
// uses in Words view. Magic words are raised letter blocks with their
// building standing on top; every other letter is a flat stone path slab.

const double isoBlockHeight = isoTileH * 0.45;
const double _slabHeight = 6;
// The buildings were designed on 60px-wide tiles.
const double isoBuildingScale = isoTileW / 60;

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

/// Everything the Village view draws, worked out from the board: pure, so
/// painting and tapping agree and both can be tested.
class VillageScene {
  VillageScene({
    required this.grid,
    required this.boardCells,
    required this.structures,
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
  final Map<String, SpriteMeta> spriteMeta;

  /// Board indices holding a letter.
  final List<int> occupied = [];

  /// The flat slabs villagers may walk on: letters that are not building
  /// blocks. A village with only buildings lets them walk on those instead.
  late final Set<int> walkable = () {
    final slabs = {for (final i in occupied) if (!blockOf.containsKey(i)) i};
    return slabs.isNotEmpty ? slabs : occupied.toSet();
  }();

  /// Cell -> the (first) building whose word uses it. Those cells are
  /// blocks; every other letter is a slab.
  final Map<int, BoardStructure> blockOf = {};

  int rowOf(int index) => index ~/ grid.boardWidth;
  int colOf(int index) => index % grid.boardWidth;
  Offset groundOf(int index) => grid.ground(rowOf(index), colOf(index));

  /// The letters of [s]'s word its building covers (spec-14): the longest
  /// stretch of its cells that no earlier building's word already uses,
  /// so two crossing buildings never stand on the same block. Usually the
  /// whole word.
  List<int> buildingCells(BoardStructure s) {
    var best = <int>[], run = <int>[];
    for (final p in s.ordered) {
      if (identical(blockOf[p], s)) {
        run = [...run, p];
        if (run.length > best.length) best = run;
      } else {
        run = [];
      }
    }
    return best;
  }

  /// Where [s]'s building stands, for [paintBuilding], or null if another
  /// building already covers all of its letters.
  BuildingSpot? spotOf(BoardStructure s) {
    final cells = buildingCells(s);
    if (cells.isEmpty) return null;
    return BuildingSpot(
      c0: colOf(cells.first) - 0.5,
      r0: rowOf(cells.first) - 0.5,
      length: cells.length,
      across: s.across,
      z0: isoBlockHeight,
      k: isoBuildingScale,
    );
  }

  /// [paintBuilding]'s projection: cell-edge coordinates to content space.
  Offset project(double c, double r, double z) => grid.ground(r, c) - Offset(0, z);

  /// The outline of [s]'s building and the blocks under it, for tapping.
  Path? buildingOutline(BoardStructure s) {
    final spot = spotOf(s);
    if (spot == null) return null;
    final c1 = spot.c0 + (spot.across ? spot.length : 1);
    final r1 = spot.r0 + (spot.across ? 1 : spot.length);
    final top = isoBlockHeight + buildingTopHeight(s.def.word, isoBuildingScale);
    return Path()
      ..addPolygon([
        project(spot.c0, spot.r0, top),
        project(c1, spot.r0, top),
        project(c1, spot.r0, 0),
        project(c1, r1, 0),
        project(spot.c0, r1, 0),
        project(spot.c0, r1, top),
      ], true);
  }

  /// The box [s]'s building is drawn in, or null if it has none.
  Rect? buildingRect(BoardStructure s) => buildingOutline(s)?.getBounds();

  /// Depth for back-to-front drawing: r + c, then c.
  double depthOf(int index) => (rowOf(index) + colOf(index)) * 100000.0 + colOf(index);

  /// A building draws just after the front-most cell of its footprint, and
  /// always after any building standing behind it (a long building's
  /// front-most cell alone can't tell which of two is in front).
  double buildingDepth(BoardStructure s) => (_buildingDepths ??= _orderBuildings())[s]!;

  Map<BoardStructure, double>? _buildingDepths;

  double _ownDepth(BoardStructure s) {
    final cells = buildingCells(s);
    return (cells.isEmpty ? s.ordered : cells).map(depthOf).reduce(max) + 0.5;
  }

  // Whether [a]'s building must be drawn after [b]'s: they overlap on
  // screen, and [a] is further along a row or column without [b] being
  // further along the other one (then they sit side by side).
  bool _inFront(BoardStructure a, BoardStructure b) {
    final fa = _footprint(a), fb = _footprint(b);
    if (fa == null || fb == null) return false;
    if (!buildingRect(a)!.overlaps(buildingRect(b)!)) return false;
    final aByRow = fa.r0 >= fb.r1, aByCol = fa.c0 >= fb.c1;
    final bByRow = fb.r0 >= fa.r1, bByCol = fb.c0 >= fa.c1;
    return (aByRow && !bByCol) || (aByCol && !bByRow);
  }

  ({double r0, double r1, double c0, double c1})? _footprint(BoardStructure s) {
    final spot = spotOf(s);
    if (spot == null) return null;
    return (
      r0: spot.r0,
      r1: spot.r0 + (spot.across ? 1 : spot.length),
      c0: spot.c0,
      c1: spot.c0 + (spot.across ? spot.length : 1),
    );
  }

  Map<BoardStructure, double> _orderBuildings() {
    final left = [...structures]..sort((a, b) => _ownDepth(a).compareTo(_ownDepth(b)));
    final depths = <BoardStructure, double>{};
    var last = double.negativeInfinity;
    while (left.isNotEmpty) {
      // The first (by own depth) with nothing still to draw behind it.
      final next = left.firstWhere(
        (s) => !left.any((o) => !identical(o, s) && _inFront(s, o)),
        orElse: () => left.first,
      );
      left.remove(next);
      last = max(_ownDepth(next), last + 0.01);
      depths[next] = last;
    }
    return depths;
  }

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

/// A villager who has moved in, as the Village view draws them.
class VillagerSprite {
  const VillagerSprite({required this.id, required this.name, this.best = false});
  final String id;
  final String name;
  final bool best;
}

/// A special tile not found yet (and a villager not met yet), drawn as a
/// faint outline through the fog.
class SpecialMarker {
  const SpecialMarker(this.cell, this.kind);
  final int cell;
  final SpecialKind kind;
}

/// Where a villager stands right now, for tapping.
class VillagerSpot {
  const VillagerSpot(this.id, this.ground);
  final String id;
  final Offset ground;
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
    this.fog,
    this.islandMap,
    this.villagers = const [],
    this.walkers,
    this.markers = const [],
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
  // spec-15 explore: fog state and island map for drawing fog overlays.
  final FogMap? fog;
  final IslandMap? islandMap;
  // spec-16: villagers who have moved in, who walks where, and what to
  // outline in the fog.
  final List<VillagerSprite> villagers;
  final VillagerWalkers? walkers;
  final List<SpecialMarker> markers;

  @override
  State<IsoVillageView> createState() => _IsoVillageViewState();
}

class _IsoVillageViewState extends State<IsoVillageView> with SingleTickerProviderStateMixin {
  late final TransformationController _ownController = TransformationController();
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.walkers?.addListener(_updateTicker);
  }

  @override
  void didUpdateWidget(IsoVillageView old) {
    super.didUpdateWidget(old);
    if (old.walkers != widget.walkers) {
      old.walkers?.removeListener(_updateTicker);
      widget.walkers?.addListener(_updateTicker);
    }
    _updateTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTicker();
  }

  // Villagers only stroll when there is someone to move and Reduce motion
  // is off; with no villagers no ticker runs at all.
  void _updateTicker() {
    final walkers = widget.walkers;
    final run = walkers != null &&
        !walkers.isEmpty &&
        widget.interactive &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (run && _ticker == null) {
      _last = Duration.zero;
      _ticker = createTicker((elapsed) {
        final dt = (elapsed - _last).inMicroseconds / 1e6;
        _last = elapsed;
        widget.walkers?.tick(dt.clamp(0.0, 0.1));
      })
        ..start();
    } else if (!run && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  TransformationController get _controller => widget.transformController ?? _ownController;

  @override
  void dispose() {
    widget.walkers?.removeListener(_updateTicker);
    _ticker?.dispose();
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
          highlight: widget.highlight,
          highlightBuilding: widget.highlightBuilding,
          fog: widget.fog,
          islandMap: widget.islandMap,
          villagers: widget.villagers,
          walkers: widget.walkers,
          markers: widget.markers,
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
    required this.highlight,
    required this.highlightBuilding,
    this.fog,
    this.islandMap,
    this.villagers = const [],
    this.walkers,
    this.markers = const [],
  }) : super(repaint: walkers);

  final VillageScene scene;
  final Rect visible;
  final double zoom;
  final Set<int> highlight;
  final BoardStructure? highlightBuilding;
  // spec-15 explore: when both are provided, fog diamonds are drawn over
  // uncleared cells and water gets a blue tint over cleared cells.
  final FogMap? fog;
  final IslandMap? islandMap;
  final List<VillagerSprite> villagers;
  final VillagerWalkers? walkers;
  final List<SpecialMarker> markers;

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
    if (fog != null) _paintFog(canvas, area, rMin, rMax, cMin, cMax);
    _paintMarkers(canvas, area);

    bool inView(int index) {
      final r = scene.rowOf(index), c = scene.colOf(index);
      return r >= rMin && r <= rMax && c >= cMin && c <= cMax && area.contains(scene.groundOf(index));
    }

    // Everything standing on the grass, back to front.
    final items = <(double, void Function())>[];
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
    for (final v in villagers) {
      final pos = walkers?.positionOf(v.id);
      if (pos == null) continue;
      final g = grid.ground(pos.r, pos.c);
      if (!area.contains(g)) continue;
      items.add((
        // In front of the flat slabs on the next diagonal (so a mid-step head
        // is never hidden under the slab being walked to), behind buildings.
        (pos.r + pos.c + 0.95) * 100000.0 + pos.c,
        () => paintVillagerFigure(canvas, g - const Offset(0, _slabHeight), v.id, v.name, best: v.best),
      ));
    }
    for (final s in scene.structures) {
      final rect = scene.buildingRect(s);
      if (rect == null || !rect.overlaps(area)) continue;
      items.add((scene.buildingDepth(s), () => _paintBuilding(canvas, s, rect)));
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

  void _paintFog(Canvas canvas, Rect area, int rMin, int rMax, int cMin, int cMax) {
    final f = fog!;
    final map = islandMap;
    // Three passes: solid fog, edge haze, water tint (cleared river cells).
    final solidPath = Path(), hazePath = Path(), waterPath = Path();
    for (int r = rMin; r <= rMax; r++) {
      for (int c = cMin; c <= cMax; c++) {
        final g = grid.ground(r, c);
        if (!area.contains(g)) continue;
        final index = r * grid.boardWidth + c;
        if (!f.isCleared(index)) {
          final d = _diamond(g, 1.0);
          if (f.canSee(index)) {
            hazePath.addPath(d, Offset.zero);
          } else {
            solidPath.addPath(d, Offset.zero);
          }
        } else if (map != null && map.isWaterIndex(index)) {
          waterPath.addPath(_diamond(g, 1.0), Offset.zero);
        }
      }
    }
    if (!solidPath.getBounds().isEmpty) {
      canvas.drawPath(solidPath, Paint()..color = const Color(0xCC555555));
    }
    if (!hazePath.getBounds().isEmpty) {
      canvas.drawPath(hazePath, Paint()..color = const Color(0x88888888));
    }
    if (!waterPath.getBounds().isEmpty) {
      canvas.drawPath(waterPath, Paint()..color = const Color(0x44448BCA));
    }
  }

  // Faint outlines of things not found yet, drawn over the fog so they show
  // through it; a villager not met yet is a pale figure once you can see them.
  void _paintMarkers(Canvas canvas, Rect area) {
    if (markers.isEmpty) return;
    final f = fog;
    for (final m in markers) {
      final g = grid.ground(m.cell ~/ grid.boardWidth, m.cell % grid.boardWidth);
      if (!area.contains(g)) continue;
      final seen = f == null || f.canSee(m.cell);
      final color = specialMarkerColor(m.kind);
      if (m.kind == SpecialKind.villager && seen) {
        paintVillagerFigure(canvas, g, 'waiting', '?', faded: true);
        continue;
      }
      final ring = Rect.fromCenter(center: g - const Offset(0, 4), width: isoTileW * 0.55, height: isoTileH * 0.55);
      canvas.drawOval(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color.withOpacity(seen ? 0.95 : 0.5),
      );
      canvas.drawOval(ring.deflate(5), Paint()..color = color.withOpacity(seen ? 0.35 : 0.18));
    }
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
        ? Offset(
            (ground.left.dx + ground.bottom.dx) / 2, (ground.left.dy + ground.bottom.dy) / 2 - isoBlockHeight / 2 - 1)
        : Offset((ground.bottom.dx + ground.right.dx) / 2,
            (ground.bottom.dy + ground.right.dy) / 2 - isoBlockHeight / 2 - 1);
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

  void _paintBuilding(Canvas canvas, BoardStructure s, Rect rect) {
    final spot = scene.spotOf(s);
    if (spot == null) return;
    if (identical(s, highlightBuilding)) {
      canvas.drawCircle(
        rect.center,
        max(rect.width, rect.height) * 0.55,
        Paint()
          ..color = WColors.sun.withOpacity(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
      );
    }
    paintBuilding(canvas, s.def.word, spot, scene.project);
  }

  @override
  bool shouldRepaint(IsoVillagePainter oldDelegate) =>
      oldDelegate.visible != visible ||
      oldDelegate.zoom != zoom ||
      !identical(oldDelegate.scene, scene) ||
      oldDelegate.highlight != highlight ||
      !identical(oldDelegate.villagers, villagers) ||
      !identical(oldDelegate.markers, markers) ||
      oldDelegate.fog != fog ||
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

class VillagerHit extends VillageHit {
  const VillagerHit(this.id);
  final String id;
}

class NoHit extends VillageHit {
  const NoHit();
}

/// Buildings first, front to back (a building's outline includes the
/// letter blocks under it). Otherwise the letter under the tap, trying the
/// point itself and then the point shifted down by the block height, so
/// the top of a raised block hits its own cell.
VillageHit hitTestVillage(Offset p, VillageScene scene, {List<VillagerSpot> villagers = const []}) {
  // Villagers first: they stand on top of the slabs.
  for (final v in villagers.reversed) {
    if (Rect.fromLTRB(v.ground.dx - 20, v.ground.dy - 54, v.ground.dx + 20, v.ground.dy + 4).contains(p)) {
      return VillagerHit(v.id);
    }
  }
  final front = [...scene.structures]..sort((a, b) => scene.buildingDepth(b).compareTo(scene.buildingDepth(a)));
  for (final s in front) {
    if (scene.buildingOutline(s)?.contains(p) ?? false) return BuildingHit(s);
  }
  for (final point in [p, p + const Offset(0, isoBlockHeight)]) {
    final cell = scene.grid.cellAt(point);
    if (cell == null) continue;
    final index = cell.r * scene.grid.boardWidth + cell.c;
    if (scene.boardCells[index] != null) return CellHit(index);
  }
  return const NoHit();
}

Color specialMarkerColor(SpecialKind kind) => switch (kind) {
      SpecialKind.chest => const Color(0xFFFFC107),
      SpecialKind.goldenSquare => const Color(0xFFFFEB3B),
      SpecialKind.boulder => const Color(0xFF9E9E9E),
      SpecialKind.shrine => const Color(0xFFB06FFF),
      SpecialKind.landmark => const Color(0xFFFF8C42),
      SpecialKind.villager => const Color(0xFFE2557A),
    };

/// A small villager standing with their feet at [base] (placeholder art).
void paintVillagerFigure(Canvas canvas, Offset base, String id, String name,
    {bool best = false, bool faded = false}) {
  final opacity = faded ? 0.55 : 1.0;
  final body = (best ? const Color(0xFFE3A6C8) : (faded ? const Color(0xFFD7D0C4) : villagerColor(id))).withOpacity(opacity);
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = WColors.ink.withOpacity(opacity);
  canvas.drawOval(
    Rect.fromCenter(center: base + const Offset(0, 1), width: 26, height: 9),
    Paint()..color = const Color(0x33000000),
  );
  final torso = RRect.fromRectAndCorners(
    Rect.fromLTWH(base.dx - 10, base.dy - 22, 20, 22),
    topLeft: const Radius.circular(10),
    topRight: const Radius.circular(10),
    bottomLeft: const Radius.circular(4),
    bottomRight: const Radius.circular(4),
  );
  canvas.drawRRect(torso, Paint()..color = body);
  canvas.drawRRect(torso, outline);
  final head = Offset(base.dx, base.dy - 31);
  canvas.drawCircle(head, 10, Paint()..color = villagerSkin.withOpacity(opacity));
  canvas.drawCircle(head, 10, outline);
  final tp = TextPainter(
    text: TextSpan(
      text: villagerInitial(name),
      style: TextStyle(fontFamily: WFonts.display, fontSize: 13, color: WColors.ink.withOpacity(opacity), height: 1.0),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  tp.paint(canvas, head - Offset(tp.width / 2, tp.height / 2));
}
