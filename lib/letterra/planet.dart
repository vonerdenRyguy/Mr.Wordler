import 'dart:math' as math;

/// Working name of the planet (spec-18, decision 11). Rename here only.
const String kPlanetName = 'Letterra';

/// Board size and the Great Lantern's cell (the planet's centre).
const int kPlanetBoard = 500;
const int kLanternRow = 250;
const int kLanternCol = 250;

/// Distance from the Lantern to every harbor.
const int kHarborDistance = 120;

/// How many harbor spots sit around the Sunny Shore.
const int kHarborSlots = 8;

/// Order family members take harbor spots: every other one first.
const List<int> kSlotOrder = [0, 4, 2, 6, 1, 5, 3, 7];

/// Half-width of an open bay, in degrees either side of its spot.
const double kBayHalfAngleDegrees = 16;

/// The bands of Letterra, from the Lantern outward (spec-18, X254).
enum Band {
  northPeak,
  cloudCap,
  echoMountains,
  ruinHills,
  ribbonRiver,
  whisperWoods,
  meadow,
  sunnyShore,
  deep;

  String get displayName => switch (this) {
        Band.northPeak => 'North Peak',
        Band.cloudCap => 'Cloud Cap',
        Band.echoMountains => 'Echo Mountains',
        Band.ruinHills => 'Ruin Hills',
        Band.ribbonRiver => 'Ribbon River',
        Band.whisperWoods => 'Whisper Woods',
        Band.meadow => 'Meadow',
        Band.sunnyShore => 'Sunny Shore',
        Band.deep => 'The Deep',
      };

  /// Outer edge of the band, as a distance from the Lantern (inclusive).
  int get outerEdge => switch (this) {
        Band.northPeak => 6,
        Band.cloudCap => 20,
        Band.echoMountains => 44,
        Band.ruinHills => 64,
        Band.ribbonRiver => 68,
        Band.whisperWoods => 94,
        Band.meadow => 116,
        Band.sunnyShore => 124,
        Band.deep => 1 << 20,
      };
}

/// The band of the board cell ([row], [col]); off the board is the Deep.
/// Round (Euclidean) distance from the Lantern, worked out in integers.
Band bandAt(int row, int col) {
  if (row < 0 || col < 0 || row >= kPlanetBoard || col >= kPlanetBoard) {
    return Band.deep;
  }
  final dr = row - kLanternRow, dc = col - kLanternCol;
  final d2 = dr * dr + dc * dc;
  for (final b in Band.values) {
    if (b == Band.deep) break;
    final e = b.outerEdge;
    if (d2 <= e * e) return b;
  }
  return Band.deep;
}

/// Angle of harbor [slot] in radians. Slot 0 points down (south) in the
/// top-down view: its direction is (row +cos, col +sin).
double slotAngle(int slot) => (slot % kHarborSlots) * math.pi / 4;

/// The board cell index of harbor [slot]: the Lantern plus 120 cells toward
/// the slot's angle.
int harborCell(int slot) {
  final a = slotAngle(slot);
  final r = (kLanternRow + kHarborDistance * math.cos(a)).round();
  final c = (kLanternCol + kHarborDistance * math.sin(a)).round();
  return r * kPlanetBoard + c;
}

/// Which harbor spots the first [members] people hold (0..8).
Set<int> takenSlotsFor(int members) =>
    kSlotOrder.take(members.clamp(0, kHarborSlots)).toSet();

/// The slot the person who joined [index]th (0-based) gets, or null when the
/// family is full.
int? slotForJoinIndex(int index) =>
    index < 0 || index >= kHarborSlots ? null : kSlotOrder[index];

bool _inWedge(int row, int col, int slot) {
  final dr = row - kLanternRow, dc = col - kLanternCol;
  if (dr == 0 && dc == 0) return false;
  var diff = math.atan2(dc.toDouble(), dr.toDouble()) - slotAngle(slot);
  while (diff > math.pi) {
    diff -= 2 * math.pi;
  }
  while (diff < -math.pi) {
    diff += 2 * math.pi;
  }
  return diff.abs() <= kBayHalfAngleDegrees * math.pi / 180;
}

bool _shoreOrMeadow(Band b) => b == Band.sunnyShore || b == Band.meadow;

/// Whether ([row], [col]) lies in the Shore/Meadow wedge of *any* of the 8
/// harbor spots (taken or not). Specials are never placed there.
bool inAnyWedge(int row, int col) {
  if (!_shoreOrMeadow(bandAt(row, col))) return false;
  for (var s = 0; s < kHarborSlots; s++) {
    if (_inWedge(row, col, s)) return true;
  }
  return false;
}

/// Whether ([row], [col]) is an open bay: the Shore/Meadow wedge of a spot
/// that nobody holds. Tiles can't go there.
bool isBay(int row, int col, Set<int> takenSlots) {
  if (!_shoreOrMeadow(bandAt(row, col))) return false;
  for (var s = 0; s < kHarborSlots; s++) {
    if (takenSlots.contains(s)) continue;
    if (_inWedge(row, col, s)) return true;
  }
  return false;
}
