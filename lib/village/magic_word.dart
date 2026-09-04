import 'package:flutter/material.dart';

// A word that, while validly placed and connected on the board, renders
// as a built structure in Village view instead of plain land. Curated
// (not algorithmic) so the set is small, named, and easy to reason about
// for a first version -- see MagicWordDef.hasAbility for which ones will
// eventually grant a passive perk (a later milestone; not implemented yet).
class MagicWordDef {
  final String word; // uppercase
  final String displayName;
  final IconData icon;
  final Color color;
  final String description;
  final bool hasAbility;

  const MagicWordDef({
    required this.word,
    required this.displayName,
    required this.icon,
    required this.color,
    required this.description,
    required this.hasAbility,
  });
}

const List<MagicWordDef> kMagicWords = [
  MagicWordDef(
    word: 'WELL',
    displayName: 'Well',
    icon: Icons.water_drop,
    color: Color(0xFF4FC3F7),
    description: 'Grants an extra letter draw.',
    hasAbility: true,
  ),
  MagicWordDef(
    word: 'FARM',
    displayName: 'Farm',
    icon: Icons.grass,
    color: Color(0xFFDCE775),
    description: 'Improves the vowel/consonant balance when your rack refills.',
    hasAbility: true,
  ),
  MagicWordDef(
    word: 'BRIDGE',
    displayName: 'Bridge',
    icon: Icons.architecture,
    color: Color(0xFFBCAAA4),
    description: 'Quick-pan to a landmark you\'ve already discovered.',
    hasAbility: true,
  ),
  MagicWordDef(
    word: 'TOWER',
    displayName: 'Tower',
    icon: Icons.fort,
    color: Color(0xFF9575CD),
    description: 'A striking landmark for your village.',
    hasAbility: false,
  ),
  MagicWordDef(
    word: 'BARN',
    displayName: 'Barn',
    icon: Icons.warehouse,
    color: Color(0xFFE57373),
    description: 'Storage for the harvest.',
    hasAbility: false,
  ),
  MagicWordDef(
    word: 'MILL',
    displayName: 'Mill',
    icon: Icons.settings,
    color: Color(0xFFA1887F),
    description: 'Grinds grain into flour.',
    hasAbility: false,
  ),
  MagicWordDef(
    word: 'HOUSE',
    displayName: 'House',
    icon: Icons.house,
    color: Color(0xFFFFB74D),
    description: 'A cozy home for villagers.',
    hasAbility: false,
  ),
  MagicWordDef(
    word: 'GARDEN',
    displayName: 'Garden',
    icon: Icons.local_florist,
    color: Color(0xFFF06292),
    description: 'A beautiful patch of flowers.',
    hasAbility: false,
  ),
];

MagicWordDef? magicWordFor(String word) {
  final upper = word.toUpperCase();
  for (final m in kMagicWords) {
    if (m.word == upper) return m;
  }
  return null;
}
