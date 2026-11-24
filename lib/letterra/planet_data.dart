import 'dart:math' as math;

import '../explore/fog.dart';
import '../players/players.dart';
import 'globe_painter.dart';
import 'planet.dart';
import 'something_to_find.dart';

/// One village to show on the planet, as its own save has it.
class PlanetVillage {
  const PlanetVillage({
    required this.player,
    required this.slot,
    this.letters = const {},
    this.runs = const [],
    this.fog,
  });

  final Player player;

  /// The harbor its letters were laid out from.
  final int slot;
  final Map<int, String> letters;
  final List<({String word, List<int> cells})> runs;
  final FogMap? fog;
}

/// Everything the turning Home planet and planet mode draw (spec-18b): your
/// village and those of the other players on this phone. Every player on one
/// phone has harbor 0 in their own save, so the others are shown at the next
/// free harbors, turned about the Lantern. Only the picture is turned; no save
/// changes.
class PlanetData {
  PlanetData._(this.villages, this.players, this.mySlot, this._slices, this.find);

  factory PlanetData.of(PlanetVillage mine, [List<PlanetVillage> others = const [], SomethingToFind? find]) {
    final villages = <GlobeVillage>[];
    final players = <int, Player>{};
    final slices = <int, _Slice>{};
    for (final v in [mine, ...others]) {
      final slot = players.containsKey(v.slot)
          ? kSlotOrder.firstWhere((s) => !players.containsKey(s), orElse: () => -1)
          : v.slot;
      if (slot < 0) break;
      final turns = (slot - v.slot) % kHarborSlots;
      // A quarter turn (two harbors) keeps letters on whole squares; an odd
      // harbor shows the houses without the letters.
      final exact = turns.isEven;
      final fog = v.fog;
      final reach = fog == null ? 1 : reachFromFog(fog, v.slot);
      players[slot] = v.player;
      slices[slot] = _Slice(exact ? fog : null, turns ~/ 2, reach);
      villages.add(GlobeVillage(
        slot: slot,
        name: v.player.name,
        color: v.player.color,
        buildings: [for (final r in v.runs.take(4)) r.word],
        reach: reach,
        letters: !exact
            ? const {}
            : turns == 0
                ? v.letters
                : {
                    for (final e in v.letters.entries)
                      if (turnedCell(e.key, turns ~/ 2) case final i?) i: e.value,
                  },
        buildingRuns: !exact
            ? const []
            : [
                for (final r in v.runs)
                  (word: r.word, cells: [for (final c in r.cells) if (turnedCell(c, turns ~/ 2) case final i?) i]),
              ],
      ));
    }
    return PlanetData._(villages, players, mine.slot, slices, find);
  }

  final List<GlobeVillage> villages;

  /// Whose village each shown harbor is.
  final Map<int, Player> players;
  final int mySlot;

  /// What glows in planet mode, if anything is left.
  final SomethingToFind? find;
  final Map<int, _Slice> _slices;

  late final Set<int> takenSlots = players.keys.toSet();

  /// Whether the Hush covers a square: each slice of the planet follows the
  /// nearest village's fog.
  bool isHushed(int row, int col, double _) {
    var slot = mySlot;
    if (_slices.length > 1) {
      final lon = math.atan2((col - kLanternCol).toDouble(), (row - kLanternRow).toDouble());
      var best = double.infinity;
      for (final s in _slices.keys) {
        final d = lonDelta(lon, slotAngle(s)).abs();
        if (d < best) {
          best = d;
          slot = s;
        }
      }
    }
    final slice = _slices[slot]!;
    final fog = slice.fog;
    if (fog == null) return hushedByReach(row, col, slice.reach);
    final i = turnedCell(row * kPlanetBoard + col, (4 - slice.quarters) % 4);
    return i == null || !fog.isCleared(i);
  }
}

class _Slice {
  const _Slice(this.fog, this.quarters, this.reach);
  final FogMap? fog;
  final int quarters;
  final int reach;
}

/// The board cell [cell] turned [quarters] quarter turns about the Lantern
/// (towards higher harbor numbers); null when that is off the board.
int? turnedCell(int cell, int quarters) {
  var dr = cell ~/ kPlanetBoard - kLanternRow, dc = cell % kPlanetBoard - kLanternCol;
  for (var i = 0; i < quarters; i++) {
    (dr, dc) = (-dc, dr);
  }
  final r = dr + kLanternRow, c = dc + kLanternCol;
  if (r < 0 || c < 0 || r >= kPlanetBoard || c >= kPlanetBoard) return null;
  return r * kPlanetBoard + c;
}

/// How Home's planet turns by itself: it rests on each village in turn (yours
/// first), and alone it makes one slow full turn back to you.
class HomeTurn {
  HomeTurn(int mySlot, Iterable<int> slots) {
    final order = slots.toSet().toList()
      ..sort((a, b) => ((a - mySlot) % kHarborSlots).compareTo((b - mySlot) % kHarborSlots));
    var at = slotAngle(mySlot);
    for (var i = 0; i < order.length; i++) {
      final gap = (order[(i + 1) % order.length] - order[i]) % kHarborSlots;
      final delta = (gap == 0 ? kHarborSlots : gap) * math.pi / 4;
      _legs.add((from: at, delta: delta, seconds: math.max(5, delta / (2 * math.pi) * 40)));
      at += delta;
    }
  }

  static const restSeconds = 5.0;
  final _legs = <({double from, double delta, double seconds})>[];

  double get totalSeconds => _legs.fold(0, (t, l) => t + restSeconds + l.seconds);

  /// The longitude facing you [seconds] into the round.
  double lonAt(double seconds) {
    var t = seconds;
    for (final l in _legs) {
      if (t <= restSeconds) return wrapLon(l.from);
      t -= restSeconds;
      if (t <= l.seconds) {
        final k = t / l.seconds;
        return wrapLon(l.from + l.delta * k * k * (3 - 2 * k));
      }
      t -= l.seconds;
    }
    return wrapLon(_legs.first.from);
  }
}
