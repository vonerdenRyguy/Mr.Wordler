import '../explore/explore_rules.dart';
import '../explore/island_map.dart';
import '../settings/word_level.dart';
import 'planet.dart';

/// The word length a [band] asks for at [level], or null when the band takes
/// no fog-clearing words (the Cloud Cap and North Peak for now, the sea).
int? bandMinLength(Band band, WordLevel level) {
  final ring = IslandMap.ringForBand(band);
  if (ring == Ring.coast) return null;
  return minLength(ring, level);
}

/// The chip text shown on the board for the band under the view's centre,
/// for example `Whisper Woods · 4+ letters`.
String bandChipText(Band band, WordLevel level, {bool bay = false}) {
  if (bay) return 'Open bay · sea';
  final n = bandMinLength(band, level);
  return switch (band) {
    Band.deep => 'The Deep · open sea',
    Band.northPeak => 'North Peak · the Great Lantern',
    Band.cloudCap => 'Cloud Cap · the Hush stays for now',
    Band.ribbonRiver => 'Ribbon River · $n+ letters to cross',
    _ => '${band.displayName} · $n+ letters',
  };
}
