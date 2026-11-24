import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../village/iso_village_view.dart' show VillagerSprite, paintVillagerFigure;
import '../villagers/walkers.dart';
import 'globe_painter.dart';

// The streets of a village on the planet (spec-22 C): what a tap finds, and
// the villagers walking on the blocks.

/// Zoom from which Build shows and the village is no longer one tap area.
const double kBuildZoom = 3;

/// Zoom from which the streets answer taps and villagers walk.
const double kStreetZoom = 7;

/// How near a tap has to be.
const double kTapReach = 28;

sealed class StreetHit {
  const StreetHit();
}

class StreetVillager extends StreetHit {
  const StreetVillager(this.id);
  final String id;
}

/// A building (its picture, or any letter of its word), by its place in
/// [GlobeVillage.buildingRuns].
class StreetBuilding extends StreetHit {
  const StreetBuilding(this.run);
  final int run;
}

class StreetLetter extends StreetHit {
  const StreetLetter(this.cell);
  final int cell;
}

/// What a tap at [p] means: a villager, else the letter right under the
/// finger, else the nearest thing within [kTapReach], buildings before letters.
StreetHit? streetHit(
  Offset p,
  GlobeProjection proj,
  GlobeVillage village, {
  Map<String, ({double r, double c})> villagers = const {},
}) {
  String? who;
  var whoD = kTapReach;
  villagers.forEach((id, at) {
    final spot = blockSpot(proj, at.r, at.c);
    if (spot == null) return;
    // Half way up the figure.
    final d = (spot.at.translate(0, -spot.cell * 0.5) - p).distance;
    if (d <= whoD) {
      whoD = d;
      who = id;
    }
  });
  if (who != null) return StreetVillager(who!);

  // The nearest block whose top is under the finger is drawn last.
  int? under;
  var underY = double.negativeInfinity;
  int? near;
  var nearD = kTapReach;
  for (final cell in village.letters.keys) {
    final top = blockTop(proj, cell);
    if (top == null) continue;
    final mid = (top[0] + top[1] + top[2] + top[3]) / 4;
    final d = (mid - p).distance;
    if (d < nearD) {
      nearD = d;
      near = cell;
    }
    if (d < 200 && mid.dy > underY && (Path()..addPolygon(top, true)).contains(p)) {
      underY = mid.dy;
      under = cell;
    }
  }
  if (under != null) return _letter(village, under);

  int? house;
  var houseD = double.infinity;
  for (var i = 0; i < village.buildingRuns.length; i++) {
    final rect = houseRect(proj, village, village.buildingRuns[i].cells);
    if (rect == null) continue;
    final d = (rect.center - p).distance;
    if ((rect.contains(p) || d <= kTapReach) && d < houseD) {
      houseD = d;
      house = i;
    }
  }
  if (house != null) return StreetBuilding(house);
  return near == null ? null : _letter(village, near);
}

StreetHit _letter(GlobeVillage v, int cell) {
  if (!v.loose.contains(cell)) {
    final run = v.buildingRuns.indexWhere((r) => r.cells.contains(cell));
    if (run >= 0) return StreetBuilding(run);
  }
  return StreetLetter(cell);
}

/// The villagers who moved in, on top of the blocks. They stroll while this
/// is on screen, and stand still with Reduce motion.
class StreetVillagers extends StatefulWidget {
  const StreetVillagers({super.key, required this.proj, required this.walkers, required this.sprites});

  final GlobeProjection proj;
  final VillagerWalkers walkers;
  final List<VillagerSprite> sprites;

  @override
  State<StreetVillagers> createState() => _StreetVillagersState();
}

class _StreetVillagersState extends State<StreetVillagers> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _last;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((now) {
      final dt = _last == null ? 0.0 : (now - _last!).inMicroseconds / 1e6;
      _last = now;
      widget.walkers.tick(dt.clamp(0.0, 0.1));
    });
  }

  void _updateTicker() {
    final run = !widget.walkers.isEmpty && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (run == _ticker.isActive) return;
    _last = null;
    run ? _ticker.start() : _ticker.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTicker();
  }

  @override
  void didUpdateWidget(StreetVillagers old) {
    super.didUpdateWidget(old);
    _updateTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _VillagersPainter(widget.proj, widget.walkers, widget.sprites),
          ),
        ),
      );
}

class _VillagersPainter extends CustomPainter {
  _VillagersPainter(this.proj, this.walkers, this.sprites) : super(repaint: walkers);

  final GlobeProjection proj;
  final VillagerWalkers walkers;
  final List<VillagerSprite> sprites;

  @override
  void paint(Canvas canvas, Size size) {
    final seen = [
      for (final s in sprites)
        if (blockSpot(proj, walkers.positionOf(s.id).r, walkers.positionOf(s.id).c) case final at?) (s, at),
    ]..sort((a, b) => a.$2.at.dy.compareTo(b.$2.at.dy));
    for (final (s, at) in seen) {
      canvas.save();
      canvas.translate(at.at.dx, at.at.dy);
      canvas.scale(at.cell / 40);
      paintVillagerFigure(canvas, Offset.zero, s.id, s.name, best: s.best);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_VillagersPainter old) => old.proj != proj || old.sprites != sprites || old.walkers != walkers;
}
