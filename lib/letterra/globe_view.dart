import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import 'globe_art.dart';
import 'globe_painter.dart';
import 'planet.dart';

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
  });

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
  State<GlobeView> createState() => _GlobeViewState();
}

/// The camera latitude that suits a zoom: tilted to show the Lantern when the
/// whole planet is in view, nearly level when zoomed into a village.
double _latForZoom(double zoom) {
  final t = ((zoom - 1.25) / 3.0).clamp(0.0, 1.0);
  return 0.46 + (0.04 - 0.46) * t;
}

class _GlobeViewState extends State<GlobeView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late double _lon = slotAngle(widget.focusSlot);
  late double _zoom = widget.initialZoom;
  late double _lat = _latForZoom(widget.initialZoom);
  double _fromLon = 0, _fromLat = 0, _fromZoom = 1;
  double _toLon = 0, _toLat = 0, _toZoom = 1;
  Size _size = const Size(400, 400);
  int _reported = -1;
  double _pinchStartZoom = 1;
  final Map<int, Offset> _pointers = {};
  double _pinchStartDistance = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    if (GlobeArt.loaded == null) {
      GlobeArt.load().then((_) {
        if (mounted) setState(() {});
      }, onError: (_) {});
    }
    _anim.addListener(() {
      final t = Curves.easeOutCubic.transform(_anim.value);
      setState(() {
        _lon = wrapLon(_fromLon + lonDelta(_fromLon, _toLon) * t);
        _lat = _fromLat + (_toLat - _fromLat) * t;
        _zoom = _fromZoom + (_toZoom - _fromZoom) * t;
      });
    });
    _anim.addStatusListener((status) {
      // Back to full detail once a fly-to settles.
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(GlobeView old) {
    super.didUpdateWidget(old);
    if (old.focusSlot != widget.focusSlot && widget.focusSlot != _reported) {
      _flyTo(lon: slotAngle(widget.focusSlot), zoom: _zoom, lat: _latForZoom(_zoom));
    }
  }

  void _flyTo({required double lon, required double zoom, required double lat}) {
    zoom = zoom.clamp(kGlobeMinZoom, kGlobeMaxZoom).toDouble();
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
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  double get _pxPerRad => GlobeProjection(size: _size, centerLon: _lon, centerLat: _lat, zoom: _zoom).pixelsPerRadian;

  // With one village alone there is nothing to spin to, so swipes go to the
  // page behind (Home's Me | Play | Family) until you have zoomed in.
  bool get _canPan => widget.villages.length > 1 || _zoom > widget.initialZoom * 1.05;

  void _zoomBy(double factor) {
    final zoom = (_zoom * factor).clamp(kGlobeMinZoom, kGlobeMaxZoom).toDouble();
    _flyTo(lon: _lon, zoom: zoom, lat: _latForZoom(zoom));
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
      _lat = (_lat + delta.dy / r).clamp(-0.25, 1.45).toDouble();
    });
  }

  void _pointerMoved(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && _pinchStartDistance > 0) {
      final pts = _pointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      setState(() {
        _zoom = (_pinchStartZoom * dist / _pinchStartDistance).clamp(kGlobeMinZoom, kGlobeMaxZoom).toDouble();
        _lat = _latForZoom(_zoom);
      });
    }
  }

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
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
      final proj = GlobeProjection(size: size, centerLon: _lon, centerLat: _lat, zoom: _zoom);
      final canPan = _canPan;
      return Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMoved,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
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
              ? (_) {
                  setState(() => _dragging = false);
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
                  label: '$kPlanetName, ${widget.villages.length} '
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
                      detail: (_anim.isAnimating || _dragging || _pointers.length > 1)
                          ? GlobeDetail.coarse
                          : GlobeDetail.fine,
                    ),
                  ),
                ),
              ),
              for (final v in widget.villages)
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
              if (widget.showZoomButtons)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ZoomButton(
                        key: const ValueKey('globe-zoom-in'),
                        icon: Icons.add,
                        label: 'Zoom in',
                        enabled: _zoom < kGlobeMaxZoom - 0.01,
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
