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
