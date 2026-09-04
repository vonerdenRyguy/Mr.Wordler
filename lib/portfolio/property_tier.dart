import 'package:flutter/material.dart';

// A single property slot's state within a neighborhood. `empty` means the
// slot hasn't been earned/bought yet.
enum PropertyTier { empty, vacantLot, cottage, house, mansion }

extension PropertyTierDisplay on PropertyTier {
  String get label {
    switch (this) {
      case PropertyTier.empty:
        return 'Empty Lot';
      case PropertyTier.vacantLot:
        return 'Vacant Lot';
      case PropertyTier.cottage:
        return 'Cottage';
      case PropertyTier.house:
        return 'House';
      case PropertyTier.mansion:
        return 'Mansion';
    }
  }

  IconData get icon {
    switch (this) {
      case PropertyTier.empty:
        return Icons.crop_square;
      case PropertyTier.vacantLot:
        return Icons.grass;
      case PropertyTier.cottage:
        return Icons.cottage;
      case PropertyTier.house:
        return Icons.house;
      case PropertyTier.mansion:
        return Icons.villa;
    }
  }

  bool get isOwned => this != PropertyTier.empty;

  // JSON is stored by tier name; kept as an explicit map (rather than
  // relying on enum index) so reordering the enum later can't silently
  // corrupt already-persisted save data.
  String get storageKey => name;

  static PropertyTier fromStorageKey(String? key) {
    return PropertyTier.values.firstWhere(
      (t) => t.name == key,
      orElse: () => PropertyTier.empty,
    );
  }
}
