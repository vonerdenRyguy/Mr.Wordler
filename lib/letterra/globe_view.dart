import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import 'close_up.dart';
import 'globe_art.dart';
import 'globe_painter.dart';
import 'planet.dart';
import 'planet_data.dart';
import 'street.dart';

/// The sky behind the planet.
const kGlobeSky = Color(0xFFBFE6F5);

/// The painted sky's lowest colour, to carry on below the picture.
const kGlobeSkyLow = Color(0xFFFFDDB8);

/// The turning, zooming globe (spec-18): draws the planet, spins freely with a
/// drag to see the other villages, zooms with a pinch or the + / - buttons
/// (still on the curved surface, down to the village's own tiles), turns to
/// [focusSlot] with a short ease (instantly when [reduceMotion]), and gives
/// every village a tap area of at least 48 x 48 (with a label for screen
/// readers).
class GlobeView extends StatefulWidget {
  const GlobeView({
    super.key,
    required this.villages,
    required this.takenSlots,
    required this.focusSlot,
    required this.isHushed,
    this.onVillageTap,
    this.onTurn,
    this.reduceMotion = false,
    this.showTags = true,
    this.initialZoom = 1.0,
    this.showZoomButtons = true,
    this.zoomButtonsBottom = 8,
    this.alwaysPan = false,
    this.turning = false,
    this.onTap,
    this.glowCells = const [],
    this.onGlowTap,
    this.closeUp = false,
    this.initialCell,
    this.marks = const [],
    this.highlight = const {},
    this.starCell,
    this.starQuiet = false,
    this.drop,
    this.onStreetTap,
    this.overlay,
    this.zoomButtonsBottomFor,
  });

  /// The board square to start on.
  final int? initialCell;

  /// See [GlobePainter].
  final List<GroundMark> marks;
  final Set<int> highlight;
  final int? starCell;
  final bool starQuiet;
  final ({List<int> cells, double t})? drop;

  /// A tap down in the streets (from [kStreetZoom] up).
  final void Function(Offset at, GlobeProjection proj)? onStreetTap;

  /// What stands over the planet, rebuilt as the camera moves: the zoom and
  /// the board square in the middle of the view.
  final List<Widget> Function(GlobeProjection proj, int cell)? overlay;

  /// Where the zoom buttons go at each zoom (else [zoomButtonsBottom]).
  final double Function(double zoom)? zoomButtonsBottomFor;

  /// Zoom on down to the streets (spec-22 C).
  final bool closeUp;

  /// Board squares that glow with a star (spec-18b), through any fog.
  final List<int> glowCells;
  final ValueChanged<int>? onGlowTap;

  /// With [onTap] the planet is only looked at (spec-18b, Home): no drag,
  /// pinch, zoom or village taps, just one tap for the whole planet.
  final VoidCallback? onTap;

  /// Turns by itself, resting on each village (see [HomeTurn]). Still with
  /// Reduce motion.
  final bool turning;

  /// Lets a lone village's planet be spun too (planet mode).
  final bool alwaysPan;
  final double zoomButtonsBottom;

  final List<GlobeVillage> villages;
  final Set<int> takenSlots;

  /// The harbor facing you.
  final int focusSlot;
  final bool Function(int row, int col, double lon) isHushed;
  final void Function(int slot)? onVillageTap;

  /// Called when a spin settles nearest another village.
  final void Function(int slot)? onTurn;
  final bool reduceMotion;
  final bool showTags;
  final double initialZoom;
  final bool showZoomButtons;

  @override
  State<GlobeView> createState() => GlobeViewState();
}

/// The camera latitude that suits a zoom: tilted to show the Lantern when the
/// whole planet is in view, nearly level when zoomed into a village.
double _latForZoom(double zoom) {
  final t = ((zoom - 1.25) / 3.0).clamp(0.0, 1.0);
  return 0.46 + (0.04 - 0.46) * t;
}

class GlobeViewState extends State<GlobeView> with TickerProviderStateMixin {
  AnimationController? _turn;
  late HomeTurn _turnPlan;
  Curve _curve = Curves.easeOutCubic;

  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late double _lon = _startAt?.lon ?? slotAngle(widget.focusSlot);
  late double _zoom = widget.initialZoom;
  late double _lat = _startAt?.lat ?? _latForZoom(widget.initialZoom);

  ({double lat, double lon})? get _startAt {
    final cell = widget.initialCell;
    return cell == null ? null : boardToSphere(cell ~/ kPlanetBoard + 0.5, cell % kPlanetBoard + 0.5);
  }

  /// How far north the camera may go (close up, right to the Lantern).
  double get _maxLat => widget.closeUp ? 1.57 : 1.45;

  /// The board square in the middle of the view.
  int get centerCell {
    final b = sphereToBoard(_lat, _lon);
    return b.row.floor().clamp(0, kPlanetBoard - 1) * kPlanetBoard + b.col.floor().clamp(0, kPlanetBoard - 1);
  }

  double get zoom => _zoom;
  double _fromLon = 0, _fromLat = 0, _fromZoom = 1;
  double _toLon = 0, _toLat = 0, _toZoom = 1;
  Size _size = const Size(400, 400);
  int _reported = -1;
  double _pinchStartZoom = 1;
  final Map<int, Offset> _pointers = {};
  double _pinchStartDistance = 0;
  bool _dragging = false;
  bool _gliding = false;

  @override
  void initState() {
    super.initState();
    if (GlobeArt.loaded == null) {
      GlobeArt.load().then((_) {
        if (mounted) setState(() {});
      }, onError: (_) {});
    }
    _anim.addListener(() {
      final t = _curve.transform(_anim.value);
      setState(() {
        _lon = wrapLon(_fromLon + lonDelta(_fromLon, _toLon) * t);
        _lat = _fromLat + (_toLat - _fromLat) * t;
        // By ratio, so the ground comes closer at an even pace.
        _zoom = _fromZoom * math.pow(_toZoom / _fromZoom, t);
      });
    });
    _anim.addStatusListener((status) {
      // Back to full detail once a fly-to settles.
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
    _planTurn();
  }

  void _planTurn() {
    if (!widget.turning || widget.reduceMotion || widget.villages.isEmpty) {
      _turn?.dispose();
      _turn = null;
      return;
    }
    _turnPlan = HomeTurn(widget.focusSlot, widget.villages.map((v) => v.slot));
    final duration = Duration(milliseconds: (_turnPlan.totalSeconds * 1000).round());
    if (_turn?.duration == duration) return;
    _turn?.dispose();
    _turn = AnimationController(vsync: this, duration: duration)
      ..addListener(() {
        final lon = _turnPlan.lonAt(_turn!.value * _turnPlan.totalSeconds);
        if (lon != _lon) setState(() => _lon = lon);
      })
      ..repeat();
  }

  /// Flies down to the village at [slot]; done when the camera is there.
  Future<void> diveTo(int slot, {int? cell}) async {
    var lat = 0.04, lon = slotAngle(slot);
    for (final v in widget.villages) {
      if (v.slot != slot || v.letters.isEmpty) continue;
      var r = 0.0, c = 0.0;
      for (final i in v.letters.keys) {
        r += i ~/ kPlanetBoard + 0.5;
        c += i % kPlanetBoard + 0.5;
      }
      final s = boardToSphere(r / v.letters.length, c / v.letters.length);
      lat = s.lat;
      lon = s.lon;
    }
    if (cell != null) {
      final s = boardToSphere(cell ~/ kPlanetBoard + 0.5, cell % kPlanetBoard + 0.5);
      lat = s.lat;
      lon = s.lon;
    }
    await _flyTo(lon: lon, zoom: _maxZoom, lat: lat, milliseconds: 1000, curve: Curves.easeInOutCubic);
  }

  /// Turns the planet so board square [cell] faces you.
  void turnTo(int cell) {
    final s = boardToSphere(cell ~/ kPlanetBoard + 0.5, cell % kPlanetBoard + 0.5);
    _flyTo(
      lon: s.lon,
      zoom: math.max(1.0, math.min(_zoom, 1.6)),
      lat: math.max(_latForZoom(1), s.lat - 0.35),
      milliseconds: 800,
      curve: Curves.easeInOutCubic,
    );
  }

  Widget? _glow(GlobeProjection proj, int cell) {
    final s = boardToSphere(cell ~/ kPlanetBoard + 0.5, cell % kPlanetBoard + 0.5);
    final at = proj.project(s.lat, s.lon);
    if (!at.front) return null;
    return Positioned.fromRect(
      rect: Rect.fromCenter(center: at.p, width: 92, height: 92),
      child: Semantics(
        button: widget.onGlowTap != null,
        label: 'Something to find',
        child: GestureDetector(
          key: ValueKey(cell == widget.glowCells.first ? 'globe-glow' : 'globe-glow-$cell'),
          onTap: widget.onGlowTap == null ? null : () => widget.onGlowTap!(cell),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0xFFFFF3B0), Color(0xBFFFD75E), Color(0x00FFD75E)],
                stops: [0, 0.45, 1],
              ),
            ),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: WColors.card,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(BorderSide(color: WColors.ink, width: 2.5)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(5),
                  child: Icon(Icons.star_rounded, color: WColors.sun, size: 26),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The whole planet again, turned to [slot].
  void showWhole(int slot) {
    _anim.stop();
    setState(() {
      _lon = slotAngle(slot);
      _zoom = 1;
      _lat = _latForZoom(1);
    });
  }

  /// Eases over to the village at [slot], a little closer in.
  void flyHome(int slot) {
    _flyTo(lon: slotAngle(slot), zoom: 1.6, lat: _latForZoom(1.6), milliseconds: 800, curve: Curves.easeInOutCubic);
  }

  @override
  void didUpdateWidget(GlobeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.villages != widget.villages || oldWidget.turning != widget.turning || oldWidget.reduceMotion != widget.reduceMotion) {
      _planTurn();
      if (widget.turning && widget.reduceMotion) _lon = slotAngle(widget.focusSlot);
    }
    if (oldWidget.focusSlot != widget.focusSlot && widget.focusSlot != _reported) {
      _flyTo(lon: slotAngle(widget.focusSlot), zoom: _zoom, lat: _latForZoom(_zoom));
    }
  }

  double get _maxZoom => widget.closeUp ? kCloseUpMaxZoom : kGlobeMaxZoom;

  /// Walks the camera to board square [cell] (the phone test's tour).
  Future<void> walkTo(int cell, double zoom, {int milliseconds = 1500}) {
    final s = boardToSphere(cell ~/ kPlanetBoard + 0.5, cell % kPlanetBoard + 0.5);
    return _flyTo(lon: s.lon, zoom: zoom, lat: s.lat, milliseconds: milliseconds, curve: Curves.easeInOutCubic);
  }

  Future<void> _flyTo({
    required double lon,
    required double zoom,
    required double lat,
    bool glide = false,
    int milliseconds = 450,
    Curve curve = Curves.easeOutCubic,
  }) async {
    zoom = zoom.clamp(kGlobeMinZoom, _maxZoom).toDouble();
    if (widget.reduceMotion) {
      _anim.stop();
      setState(() {
        _lon = wrapLon(lon);
        _lat = lat;
        _zoom = zoom;
      });
      return;
    }
    _fromLon = _lon;
    _fromLat = _lat;
    _fromZoom = _zoom;
    _toLon = lon;
    _toLat = lat;
    _toZoom = zoom;
    _gliding = glide;
    _curve = curve;
    _anim.duration = Duration(milliseconds: glide ? 900 : milliseconds);
    await _anim.forward(from: 0).orCancel.catchError((_) {});
  }

  @override
  void dispose() {
    _turn?.dispose();
    _anim.dispose();
    super.dispose();
  }

  double get _pxPerRad => GlobeProjection(size: _size, centerLon: _lon, centerLat: _lat, zoom: _zoom, closeUp: widget.closeUp).pixelsPerRadian;

  // With one village alone there is nothing to spin to, so swipes go to the
  // page behind (Home's Me | Play | Family) until you have zoomed in.
  bool get _canPan => widget.alwaysPan || widget.villages.length > 1 || _zoom > widget.initialZoom * 1.05;

  void _zoomBy(double factor) {
    final zoom = (_zoom * factor).clamp(kGlobeMinZoom, _maxZoom).toDouble();
    // Close up, keep where you were looking; only the tilt follows the zoom.
    final lat = widget.closeUp
        ? (_lat + _latForZoom(zoom) - _latForZoom(_zoom)).clamp(-0.25, _maxLat).toDouble()
        : _latForZoom(zoom);
    _flyTo(lon: _lon, zoom: zoom, lat: lat);
  }

  int? _nearestVillage() {
    int? best;
    var bestDelta = double.infinity;
    for (final v in widget.villages) {
      final d = lonDelta(_lon, slotAngle(v.slot)).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = v.slot;
      }
    }
    return best;
  }

  void _panBy(Offset delta) {
    final r = _pxPerRad;
    final cosLat = math.max(0.25, math.cos(_lat));
    setState(() {
      _lon = wrapLon(_lon - delta.dx / (r * cosLat));
      _lat = (_lat + delta.dy / r).clamp(-0.25, _maxLat).toDouble();
    });
  }

  // Let go while moving and the planet glides on, easing to a stop. The glide
  // starts at the finger's own speed (easeOutCubic starts at 3 / duration).
  void _glide(Offset velocity) {
    if (widget.reduceMotion || velocity.distance < 120) return;
    final r = _pxPerRad;
    final turn = (-velocity.dx * 0.3 / (r * math.max(0.25, math.cos(_lat)))).clamp(-2.4, 2.4).toDouble();
    final lat = (_lat + velocity.dy * 0.3 / r).clamp(-0.25, _maxLat).toDouble();
    _flyTo(lon: _lon + turn, zoom: _zoom, lat: lat, glide: true);
  }

  void _pointerMoved(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && _pinchStartDistance > 0) {
      final pts = _pointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      setState(() {
        final before = _latForZoom(_zoom);
        _zoom = (_pinchStartZoom * dist / _pinchStartDistance).clamp(kGlobeMinZoom, _maxZoom).toDouble();
        // Keep where you were looking; only the tilt follows the zoom.
        _lat = (_lat + _latForZoom(_zoom) - before).clamp(-0.25, _maxLat).toDouble();
      });
    }
  }

  void _pointerDown(PointerDownEvent e) {
    if (widget.onTap != null) return;
    _pointers[e.pointer] = e.position;
    if (_gliding) {
      _gliding = false;
      _anim.stop();
    }
    if (_pointers.length == 2) {
      _anim.stop();
      final pts = _pointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartZoom = _zoom;
    }
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    _pinchStartDistance = 0;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      _size = size;
      final proj = GlobeProjection(size: size, centerLon: _lon, centerLat: _lat, zoom: _zoom, closeUp: widget.closeUp);
      final look = widget.onTap != null;
      final canPan = !look && _canPan;
      return Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMoved,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapUp: widget.onStreetTap == null || _zoom < kStreetZoom
              ? null
              : (d) => widget.onStreetTap!(d.localPosition, proj),
          onPanStart: canPan
              ? (_) {
                  _anim.stop();
                  setState(() => _dragging = true);
                }
              : null,
          onPanUpdate: canPan
              ? (d) {
                  if (_pointers.length < 2) _panBy(d.delta);
                }
              : null,
          onPanEnd: canPan
              ? (d) {
                  setState(() => _dragging = false);
                  _glide(d.velocity.pixelsPerSecond);
                  final near = _nearestVillage();
                  if (near != null && near != _reported && widget.villages.length > 1) {
                    _reported = near;
                    widget.onTurn?.call(near);
                  }
                }
              : null,
          child: Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  button: look,
                  label: '${look ? 'Open the planet. ' : ''}$kPlanetName, ${widget.villages.length} '
                      '${widget.villages.length == 1 ? 'village' : 'villages'}',
                  child: CustomPaint(
                    painter: GlobePainter(
                      centerLon: _lon,
                      centerLat: _lat,
                      zoom: _zoom,
                      villages: widget.villages,
                      takenSlots: widget.takenSlots,
                      isHushed: widget.isHushed,
                      showTags: widget.showTags,
                      art: GlobeArt.loaded,
                      closeUp: widget.closeUp,
                      marks: widget.marks,
                      highlight: widget.highlight,
                      starCell: widget.starCell,
                      starQuiet: widget.starQuiet,
                      drop: widget.drop,
                      detail: (_turn != null || _anim.isAnimating || _dragging || _pointers.length > 1)
                          ? GlobeDetail.coarse
                          : GlobeDetail.fine,
                    ),
                  ),
                ),
              ),
              if (!look)
                for (final cell in widget.glowCells)
                  if (_glow(proj, cell) case final glow?) glow,
              for (final v in look ? const <GlobeVillage>[] : widget.villages)
                if (widget.onStreetTap == null || _zoom < (v.slot == widget.focusSlot ? kBuildZoom : kStreetZoom))
                  if (proj.villageHit(v.slot) case final rect?)
                  Positioned.fromRect(
                    rect: rect,
                    child: Semantics(
                      button: true,
                      label: "Open ${v.name}'s village",
                      child: GestureDetector(
                        key: ValueKey('globe-village-${v.slot}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onVillageTap?.call(v.slot),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
              if (widget.showZoomButtons && !look)
                Positioned(
                  right: 8,
                  bottom: widget.zoomButtonsBottomFor?.call(_zoom) ?? widget.zoomButtonsBottom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ZoomButton(
                        key: const ValueKey('globe-zoom-in'),
                        icon: Icons.add,
                        label: 'Zoom in',
                        enabled: _zoom < _maxZoom - 0.01,
                        onTap: () => _zoomBy(1.7),
                      ),
                      const SizedBox(height: 6),
                      _ZoomButton(
                        key: const ValueKey('globe-zoom-out'),
                        icon: Icons.remove,
                        label: 'Zoom out',
                        enabled: _zoom > kGlobeMinZoom + 0.01,
                        onTap: () => _zoomBy(1 / 1.7),
                      ),
                    ],
                  ),
                ),
              ...?widget.overlay?.call(proj, centerCell),
            ],
          ),
        ),
      );
    });
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({super.key, required this.icon, required this.label, required this.enabled, required this.onTap});

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: enabled ? WColors.card : WColors.boardCell,
            shape: BoxShape.circle,
            border: Border.all(color: WColors.ink, width: 2.5),
            boxShadow: wLip(3),
          ),
          child: Icon(icon, color: enabled ? WColors.ink : WColors.muted, size: 28),
        ),
      ),
    );
  }
}
