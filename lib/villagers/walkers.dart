import 'dart:math' as math;

import 'package:flutter/foundation.dart';

// Villagers strolling along the word slabs in Village view (spec-16). Pure
// movement: which cell each one is on, which neighbouring slab they are
// walking to and how far along. They only ever step between slabs (never
// grass, never fog: fog hides nothing here because slabs are only ever on
// squares you could reach). The view ticks [tick] with the time passed;
// with Reduce motion it never does, so they stand still.

/// Seconds to walk one square.
const kSecondsPerStep = 1.5;

class _Walker {
  _Walker(this.home, this.rng);

  final int home;
  final math.Random rng;
  int? cur;
  int? next;
  double t = 0;
  double wait = 0;
}

class VillagerWalkers extends ChangeNotifier {
  VillagerWalkers({this.boardWidth = 500, int seed = 16}) : _seed = seed;

  final int boardWidth;
  final int _seed;
  final Map<String, _Walker> _walkers = {};
  Set<int> _walkable = const {};

  bool get isEmpty => _walkers.isEmpty;

  /// Updates who lives where ([homes]: id -> the square they moved in on)
  /// and which squares they may walk on. Anyone whose square is no longer
  /// walkable is put on the nearest one.
  void sync(Map<String, int> homes, Set<int> walkable) {
    _walkable = walkable;
    _walkers.removeWhere((id, _) => !homes.containsKey(id));
    homes.forEach((id, home) {
      final w = _walkers.putIfAbsent(id, () => _Walker(home, math.Random(Object.hash(_seed, id))));
      final c = w.cur;
      if (c == null || !walkable.contains(c) || (w.next != null && !walkable.contains(w.next))) {
        w.cur = _nearest(home, walkable);
        w.next = null;
        w.t = 0;
        w.wait = 0.5 + w.rng.nextDouble() * 1.5;
      }
    });
    notifyListeners();
  }

  int? _nearest(int home, Set<int> walkable) {
    if (walkable.isEmpty) return null;
    final hr = home ~/ boardWidth, hc = home % boardWidth;
    int? best;
    var bestD = 1 << 30;
    for (final c in walkable) {
      final d = math.max((c ~/ boardWidth - hr).abs(), (c % boardWidth - hc).abs()) * 1000 +
          (c ~/ boardWidth - hr).abs() +
          (c % boardWidth - hc).abs();
      if (d < bestD || (d == bestD && c < best!)) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  /// The slab [id] is standing on or leaving (null: nowhere to walk yet).
  int? cellOf(String id) => _walkers[id]?.cur;

  /// Fractional (row, col) of [id] now, or their home square if there is no
  /// slab for them.
  ({double r, double c}) positionOf(String id) {
    final w = _walkers[id];
    if (w == null) return (r: 0, c: 0);
    final cur = w.cur ?? w.home;
    final n = w.next;
    final r0 = (cur ~/ boardWidth).toDouble(), c0 = (cur % boardWidth).toDouble();
    if (n == null) return (r: r0, c: c0);
    final r1 = (n ~/ boardWidth).toDouble(), c1 = (n % boardWidth).toDouble();
    final t = _ease(w.t);
    return (r: r0 + (r1 - r0) * t, c: c0 + (c1 - c0) * t);
  }

  Iterable<String> get ids => _walkers.keys;

  /// Moves everyone on by [dt] seconds.
  void tick(double dt) {
    var moved = false;
    for (final w in _walkers.values) {
      if (w.cur == null) continue;
      if (w.next != null) {
        w.t += dt / kSecondsPerStep;
        moved = true;
        if (w.t >= 1) {
          w.cur = w.next;
          w.next = null;
          w.t = 0;
          w.wait = w.rng.nextDouble() * 2.5; // a breather now and then
        }
      } else {
        w.wait -= dt;
        if (w.wait <= 0) {
          final options = _neighbours(w.cur!);
          if (options.isEmpty) {
            w.wait = 2; // nowhere to go; look again later
          } else {
            w.next = options[w.rng.nextInt(options.length)];
            w.t = 0;
          }
        }
      }
    }
    if (moved) notifyListeners();
  }

  List<int> _neighbours(int cell) {
    final r = cell ~/ boardWidth, c = cell % boardWidth;
    return [
      for (final (dr, dc) in const [(0, 1), (1, 0), (0, -1), (-1, 0)])
        if (r + dr >= 0 && c + dc >= 0 && c + dc < boardWidth && _walkable.contains((r + dr) * boardWidth + c + dc))
          (r + dr) * boardWidth + c + dc,
    ];
  }
}

// A smooth ease without importing the widgets library into this pure file.
double _ease(double t) => t * t * (3 - 2 * t);
