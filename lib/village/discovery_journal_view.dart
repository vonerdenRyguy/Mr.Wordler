import 'dart:math';

import 'package:flutter/material.dart';

import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import 'magic_word.dart';

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
  });

  final List<String?> rackCells;
  final Set<String> discoveredWords;

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
              const Text('Magic words that can be built into structures.', style: WText.label),
              const SizedBox(height: 12),
              for (final def in kMagicWords)
                _JournalEntry(
                  def: def,
                  isDiscovered: discoveredWords.contains(def.word),
                  lettersHave: lettersTowardWord(def.word, rackCells),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _JournalEntry extends StatelessWidget {
  const _JournalEntry({required this.def, required this.isDiscovered, required this.lettersHave});

  final MagicWordDef def;
  final bool isDiscovered;
  final int lettersHave;

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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
