import 'package:flutter/material.dart';

import 'globe_painter.dart';
import 'planet.dart';

/// The turning globe (spec-18): draws the planet, turns to [focusSlot] with a
/// short ease (instantly when [reduceMotion]), lets a swipe turn it to the
/// next filled harbor, and gives every village a tap area of at least
/// 48 x 48 (with a label for screen readers).
class GlobeView extends StatefulWidget {
  const GlobeView({
    super.key,
    required this.mode,
    required this.villages,
    required this.takenSlots,
    required this.focusSlot,
    required this.isHushed,
    this.onVillageTap,
    this.onTurn,
    this.reduceMotion = false,
    this.showTags = true,
  });

  final GlobeMode mode;
  final List<GlobeVillage> villages;
  final Set<int> takenSlots;

  /// The harbor facing you.
  final int focusSlot;
  final bool Function(int row, int col, double lon) isHushed;
  final void Function(int slot)? onVillageTap;

  /// Called when a swipe settles on another filled harbor.
  final void Function(int slot)? onTurn;
  final bool reduceMotion;
  final bool showTags;

  @override
  State<GlobeView> createState() => _GlobeViewState();
}

class _GlobeViewState extends State<GlobeView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late double _lon = slotAngle(widget.focusSlot);
  double _from = 0;
  double _delta = 0;
  double _radius = 300;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (_anim.isAnimating || _anim.isCompleted) {
        setState(() => _lon = wrapLon(_from + _delta * Curves.easeOutCubic.transform(_anim.value)));
      }
    });
  }

  @override
  void didUpdateWidget(GlobeView old) {
    super.didUpdateWidget(old);
    if (old.focusSlot != widget.focusSlot) _turnTo(slotAngle(widget.focusSlot));
  }

  void _turnTo(double target) {
    final delta = lonDelta(_lon, target);
    if (widget.reduceMotion || delta.abs() < 1e-6) {
      _anim.stop();
      setState(() => _lon = wrapLon(target));
      return;
    }
    _from = _lon;
    _delta = delta;
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  List<int> get _filled => (widget.villages.map((v) => v.slot).toList()..sort());

  void _settle(double velocity) {
    final filled = _filled;
    if (filled.isEmpty) return;
    int target;
    if (velocity.abs() > 400 && filled.length > 1) {
      // A fling goes to the next filled harbor that way round.
      final i = filled.indexOf(widget.focusSlot);
      final from = i < 0 ? 0 : i;
      final step = velocity > 0 ? -1 : 1;
      target = filled[(from + step) % filled.length];
    } else {
      target = filled.reduce((a, b) =>
          lonDelta(_lon, slotAngle(a)).abs() <= lonDelta(_lon, slotAngle(b)).abs() ? a : b);
    }
    _turnTo(slotAngle(target));
    if (target != widget.focusSlot) widget.onTurn?.call(target);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      final proj = GlobeProjection(size: size, centerLon: _lon, mode: widget.mode);
      _radius = proj.radius;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _anim.stop(),
        onHorizontalDragUpdate: (d) => setState(() => _lon = wrapLon(_lon - d.delta.dx / _radius)),
        onHorizontalDragEnd: (d) {
          if (widget.mode == GlobeMode.closeUp) {
            _settle(d.primaryVelocity ?? 0);
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: '$kPlanetName, ${widget.villages.length} '
                    '${widget.villages.length == 1 ? 'village' : 'villages'}',
                child: CustomPaint(
                  painter: GlobePainter(
                    mode: widget.mode,
                    centerLon: _lon,
                    villages: widget.villages,
                    takenSlots: widget.takenSlots,
                    isHushed: widget.isHushed,
                    showTags: widget.showTags,
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
          ],
        ),
      );
    });
  }
}
