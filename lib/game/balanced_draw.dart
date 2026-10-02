import 'dart:math';

// Infinite Estate's rack refill rules (see GridConfig.balancedRefill). A
// plain random draw lets hard letters pile up until the player is stuck;
// these rules keep a few vowels in the rack and cap the hard letters,
// while still never leaving a slot empty when the pool has letters.

const Set<String> kVowels = {'A', 'E', 'I', 'O', 'U'};
const Set<String> kHardLetters = {'J', 'K', 'Q', 'V', 'X', 'Z'};

/// Removes and returns one letter from [pool] following the balanced-refill
/// rules. [rack] is the rack as it will be once the slot is filled, minus
/// that slot. Uses [random] for every random choice so tests can seed it.
String drawBalanced(List<String> pool, List<String?> rack, Random random) {
  if (pool.isEmpty) {
    throw StateError('drawBalanced called with an empty pool');
  }
  final rackLetters = rack.whereType<String>().toList();
  final vowelCount = rackLetters.where(kVowels.contains).length;
  final hardInRack = rackLetters.where(kHardLetters.contains).toSet();
  final hardCount = rackLetters.where(kHardLetters.contains).length;
  final hasU = rackLetters.contains('U');

  // null = either type is fine.
  final bool? wantVowel = vowelCount < 3 ? true : (vowelCount >= 5 ? false : null);

  bool passesHardRules(String letter) {
    if (!kHardLetters.contains(letter)) return true;
    if (hardCount >= 2) return false;
    if (hardInRack.contains(letter)) return false;
    if (letter == 'Q' && !hasU) return false;
    return true;
  }

  bool passesType(String letter) => wantVowel == null || kVowels.contains(letter) == wantVowel;

  List<int> indicesWhere(bool Function(String) test) => [
        for (int i = 0; i < pool.length; i++)
          if (test(pool[i])) i,
      ];

  var candidates = indicesWhere((l) => passesType(l) && passesHardRules(l));
  if (candidates.isEmpty) candidates = indicesWhere(passesHardRules);
  if (candidates.isEmpty) candidates = [for (int i = 0; i < pool.length; i++) i];

  return pool.removeAt(candidates[random.nextInt(candidates.length)]);
}
