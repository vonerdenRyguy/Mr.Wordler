import 'planet.dart';

/// The gold star a brand-new village's first word must cover (spec-18b):
/// the harbor's own square, or the nearest land square that is free.
int goldStarCell(int slot, {required bool Function(int cell) isSea, Set<int> taken = const {}}) {
  final home = harborCell(slot);
  for (var ring = 0; ring <= 30; ring++) {
    for (var dr = -ring; dr <= ring; dr++) {
      for (var dc = -ring; dc <= ring; dc++) {
        if (dr.abs() != ring && dc.abs() != ring) continue;
        final i = home + dr * kPlanetBoard + dc;
        if (!isSea(i) && !taken.contains(i)) return i;
      }
    }
  }
  return home;
}
