import '../letterra/globe_painter.dart' show reachOfBand;
import '../letterra/planet.dart';
import 'fog.dart';

/// Coins the first time a village's cleared land reaches a region (spec-18b).
const kRegionCoins = 15;

/// Every region (as a reach number, see `reachName`) with cleared land.
Set<int> regionsCleared(FogMap fog) {
  final out = <int>{};
  for (var r = kLanternRow - 124; r <= kLanternRow + 124; r++) {
    for (var c = kLanternCol - 124; c <= kLanternCol + 124; c++) {
      if (!fog.isCleared(r * kPlanetBoard + c)) continue;
      final band = bandAt(r, c);
      if (band != Band.deep) out.add(reachOfBand(band));
    }
  }
  return out;
}
