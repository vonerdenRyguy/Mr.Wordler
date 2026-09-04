import 'neighborhood.dart';
import 'property_tier.dart';

// Immutable snapshot of everything the Portfolio meta-layer tracks:
// currency, XP, and each neighborhood's slot tiers. This is exactly what
// gets persisted (as JSON via shared_preferences).
class PortfolioData {
  final int currency;
  final int totalXp;
  final Map<String, List<PropertyTier>> neighborhoodSlots;

  const PortfolioData({
    required this.currency,
    required this.totalXp,
    required this.neighborhoodSlots,
  });

  // A fresh player: every slot in every neighborhood is empty.
  factory PortfolioData.initial() {
    return PortfolioData(
      currency: 0,
      totalXp: 0,
      neighborhoodSlots: {
        for (final n in kNeighborhoods)
          n.id: List<PropertyTier>.filled(n.slotCount, PropertyTier.empty),
      },
    );
  }

  bool isNeighborhoodComplete(String neighborhoodId) {
    final slots = neighborhoodSlots[neighborhoodId];
    if (slots == null || slots.isEmpty) return false;
    return slots.every((tier) => tier.isOwned);
  }

  int emptySlotCount(String neighborhoodId) {
    return neighborhoodSlots[neighborhoodId]?.where((t) => !t.isOwned).length ?? 0;
  }

  PortfolioData copyWith({
    int? currency,
    int? totalXp,
    Map<String, List<PropertyTier>>? neighborhoodSlots,
  }) {
    return PortfolioData(
      currency: currency ?? this.currency,
      totalXp: totalXp ?? this.totalXp,
      neighborhoodSlots: neighborhoodSlots ?? this.neighborhoodSlots,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currency': currency,
      'totalXp': totalXp,
      'neighborhoodSlots': neighborhoodSlots.map(
        (id, tiers) => MapEntry(id, tiers.map((t) => t.storageKey).toList()),
      ),
    };
  }

  factory PortfolioData.fromJson(Map<String, dynamic> json) {
    final base = PortfolioData.initial();
    final rawSlots = json['neighborhoodSlots'] as Map<String, dynamic>?;
    final slots = <String, List<PropertyTier>>{};
    for (final n in kNeighborhoods) {
      final stored = rawSlots?[n.id] as List<dynamic>?;
      if (stored == null) {
        slots[n.id] = base.neighborhoodSlots[n.id]!;
        continue;
      }
      // If a neighborhood's slotCount ever changes, pad/truncate stored
      // data to match rather than crashing on old save data.
      final tiers = List<PropertyTier>.generate(n.slotCount, (i) {
        if (i >= stored.length) return PropertyTier.empty;
        return PropertyTierDisplay.fromStorageKey(stored[i] as String?);
      });
      slots[n.id] = tiers;
    }
    return PortfolioData(
      currency: json['currency'] as int? ?? 0,
      totalXp: json['totalXp'] as int? ?? 0,
      neighborhoodSlots: slots,
    );
  }
}
