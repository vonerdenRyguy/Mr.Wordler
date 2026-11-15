import '../portfolio/property_tier.dart';

// Property tier awarded for a Daily Estate Challenge attempt: no tile at
// all if the player didn't empty the pool; otherwise a tier based on how
// fast they finished, bumped up one tier if they included the bonus word.
PropertyTier tierForDailyResult({
  required bool completed,
  required Duration time,
  required bool bonusWordFound,
}) {
  if (!completed) return PropertyTier.empty;

  PropertyTier base;
  if (time <= const Duration(minutes: 3)) {
    base = PropertyTier.house;
  } else if (time <= const Duration(minutes: 6)) {
    base = PropertyTier.cottage;
  } else {
    base = PropertyTier.vacantLot;
  }

  if (!bonusWordFound) return base;
  final upgradedIndex = (base.index + 1).clamp(0, PropertyTier.values.length - 1);
  return PropertyTier.values[upgradedIndex];
}

// Coins for finishing the Daily with the secret word on the board
// (spec-05). Clues are free and never lower the prize step; each one used
// just makes this bonus a little smaller.
int secretWordCoins(int cluesUsed) {
  const coins = [20, 15, 10, 5];
  return coins[cluesUsed.clamp(0, 3)];
}
