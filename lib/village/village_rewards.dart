import 'structures.dart';

// Infinite Estate's small rewards, as pure rules so they're easy to test.

const int firstBuildingCoins = 10;
const int swapCoinCost = 5;

/// Magic words built now that have never been built before. Words already
/// in [discovered] (including from older saves) never count again.
Set<String> newDiscoveries(List<BoardStructure> structures, Set<String> discovered) =>
    structures.map((s) => s.def.word).where((w) => !discovered.contains(w)).toSet();

/// Coins for building [words] for the first time.
int coinsForDiscoveries(Set<String> words) => words.length * firstBuildingCoins;

/// Free Swaps each visit: 1 for everyone, 2 with a Farm.
int freeSwapsPerVisit({required bool hasFarm}) => hasFarm ? 2 : 1;

/// How many free Swaps are left this visit.
int freeSwapsLeft({required int used, required bool hasFarm}) =>
    (freeSwapsPerVisit(hasFarm: hasFarm) - used).clamp(0, 2);

/// What the next Swap costs: free ones are used before coins.
int nextSwapCost({required int used, required bool hasFarm}) =>
    freeSwapsLeft(used: used, hasFarm: hasFarm) > 0 ? 0 : swapCoinCost;
