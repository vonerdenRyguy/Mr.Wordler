import 'dart:math';

import 'package:flutter/material.dart';

import '../explore/island_map.dart' show LandmarkKind;
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import 'magic_word.dart';
import 'village_cards.dart';

// How many of `word`'s letters (respecting duplicates -- two A's needed
// means two A's in hand, not one) are currently in the player's rack.
// Used to show "3 of 4 letters needed" without requiring the player to
// count their own rack by eye.
int lettersTowardWord(String word, List<String?> rackCells) {
  final rackCounts = <String, int>{};
  for (final c in rackCells) {
    if (c != null) rackCounts[c] = (rackCounts[c] ?? 0) + 1;
  }
  final needed = <String, int>{};
  for (final ch in word.split('')) {
    needed[ch] = (needed[ch] ?? 0) + 1;
  }
  int have = 0;
  needed.forEach((letter, count) {
    have += min(count, rackCounts[letter] ?? 0);
  });
  return have;
}

// A scrollable sheet listing every magic word, whether it's been
// discovered (built at least once, ever) yet, and -- for ones not yet
// discovered -- how close the player's current hand is to being able to
// spell it. Deliberately shows the word/letters needed rather than
// hiding them: the point is to make "save up for this word" visible, not
// to turn it into a guessing game.
class DiscoveryJournalView extends StatelessWidget {
  const DiscoveryJournalView({
    super.key,
    required this.rackCells,
    required this.discoveredWords,
    this.foundLandmarks = const {},
    this.loadDefinition,
    this.villagersMet = 0,
    this.villagersTotal = 0,
    this.onVillagers,
  });

  final List<String?> rackCells;
  final Set<String> discoveredWords;
  // spec-15: landmarks found on the island.
  final Set<LandmarkKind> foundLandmarks;
  // spec-16: a row that opens Your villagers; hidden when [onVillagers] is null.
  final int villagersMet;
  final int villagersTotal;
  final VoidCallback? onVillagers;
  // For each row's "What it means" link; null hides the link.
  final DefinitionLoader? loadDefinition;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: WColors.card,
            border: Border(top: BorderSide(color: WColors.ink, width: WSize.outline)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(WSize.radiusHero)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16.0),
            children: [
              Semantics(header: true, child: const Text('Discovery Journal', style: WText.heading)),
              const SizedBox(height: 4),
              const Text('Magic words and island discoveries.', style: WText.label),
              if (onVillagers != null) ...[
                const SizedBox(height: 12),
                ChunkyCard(
                  onTap: onVillagers,
                  child: Row(
                    children: [
                      const Icon(Icons.people, color: WColors.ink),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Villagers', style: WText.bodyBold)),
                      Text('$villagersMet/$villagersTotal', style: WText.button),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: WColors.ink),
                    ],
                  ),
                ),
              ],
              if (foundLandmarks.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Landmarks', style: WText.bodyBold),
                const SizedBox(height: 8),
                for (final lk in LandmarkKind.values)
                  if (foundLandmarks.contains(lk))
                    _LandmarkEntry(kind: lk),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              const Text('Buildings', style: WText.bodyBold),
              const SizedBox(height: 8),
              for (final def in kMagicWords)
                _JournalEntry(
                  def: def,
                  isDiscovered: discoveredWords.contains(def.word),
                  lettersHave: lettersTowardWord(def.word, rackCells),
                  onWhatItMeans: loadDefinition == null
                      ? null
                      : () => showVillageSheet<void>(context, MeaningCard(word: def.word, loadDefinition: loadDefinition!)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LandmarkEntry extends StatelessWidget {
  const _LandmarkEntry({required this.kind});

  final LandmarkKind kind;

  static const _icons = {
    LandmarkKind.giantOak: Icons.park,
    LandmarkKind.waterfall: Icons.water,
    LandmarkKind.windmill: Icons.wind_power,
    LandmarkKind.castle: Icons.castle,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WSize.gap2),
      child: ChunkyCard(
        color: const Color(0xFFFFF8E1),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: WColors.sun,
                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icons[kind] ?? Icons.star, color: WColors.ink, size: 22),
            ),
            const SizedBox(width: WSize.gap3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind.displayName, style: WText.bodyBold),
                  Text('Landmark discovered!', style: WText.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalEntry extends StatelessWidget {
  const _JournalEntry({required this.def, required this.isDiscovered, required this.lettersHave, this.onWhatItMeans});

  final MagicWordDef def;
  final bool isDiscovered;
  final int lettersHave;
  final VoidCallback? onWhatItMeans;

  @override
  Widget build(BuildContext context) {
    final needed = def.word.length;
    final ready = lettersHave >= needed;
    return Padding(
      padding: const EdgeInsets.only(bottom: WSize.gap2),
      child: ChunkyCard(
        color: isDiscovered ? WColors.card : WColors.paper,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: def.color,
                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(def.icon, color: WColors.ink, size: 24),
            ),
            const SizedBox(width: WSize.gap3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def.displayName, style: WText.bodyBold),
                  Text(def.description, style: WText.body.copyWith(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    isDiscovered ? 'Discovered!' : '$lettersHave of $needed letters needed',
                    style: WText.label.copyWith(
                      color: isDiscovered ? WColors.grass : (ready ? WColors.ink : WColors.muted),
                    ),
                  ),
                  if (onWhatItMeans != null)
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onWhatItMeans,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'What it means',
                            style: WText.label.copyWith(color: WColors.ink, decoration: TextDecoration.underline),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
