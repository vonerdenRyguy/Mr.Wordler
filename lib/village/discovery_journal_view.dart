import 'dart:math';

import 'package:flutter/material.dart';

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
            color: Color(0xFFFFFDE7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16.0),
            children: [
              const Text('Discovery Journal',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              const SizedBox(height: 4),
              const Text('Magic words that can be built into structures.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
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
    return Card(
      color: isDiscovered ? Colors.white : Colors.grey.shade100,
      margin: const EdgeInsets.only(bottom: 10.0),
      child: ListTile(
        leading: Icon(def.icon, color: isDiscovered ? def.color : Colors.grey),
        title: Text(def.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(def.description, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              isDiscovered ? 'Discovered!' : '$lettersHave of $needed letters needed',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isDiscovered
                    ? Colors.green.shade700
                    : (ready ? Colors.orange.shade800 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
