import 'package:flutter/material.dart';

// A themed, color-grouped set of property slots (Monopoly-style color
// groups). The catalog is fixed/static -- only which tier each slot has
// reached is persisted per-player.
class Neighborhood {
  final String id;
  final String name;
  final Color color;
  final int slotCount;
  final String perkDescription;

  const Neighborhood({
    required this.id,
    required this.name,
    required this.color,
    required this.slotCount,
    required this.perkDescription,
  });
}

// The full set of neighborhoods in the game. Kept small for a first
// version; add more here later without touching any other Portfolio code.
const List<Neighborhood> kNeighborhoods = [
  Neighborhood(
    id: 'ocean_ave',
    name: 'Ocean Ave',
    color: Colors.lightBlue,
    slotCount: 3,
    perkDescription: '+15s starting time in Time Attack',
  ),
  Neighborhood(
    id: 'downtown',
    name: 'Downtown',
    color: Colors.purple,
    slotCount: 3,
    perkDescription: '+10% score in Infinite Estate',
  ),
  Neighborhood(
    id: 'old_town',
    name: 'Old Town',
    color: Colors.brown,
    slotCount: 3,
    perkDescription: 'One free trade-in per round',
  ),
];

Neighborhood? neighborhoodById(String id) {
  for (final n in kNeighborhoods) {
    if (n.id == id) return n;
  }
  return null;
}
