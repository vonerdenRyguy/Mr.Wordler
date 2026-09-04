import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'portfolio_data.dart';
import 'property_tier.dart';

// Global (not per-screen-scoped, unlike the grid game engine) -- the
// player's Portfolio persists across the whole app session and every
// mode. Persisted as a single JSON blob via shared_preferences, matching
// the storage pattern the leaderboard already uses elsewhere in the app.
class PortfolioController extends StateNotifier<PortfolioData> {
  PortfolioController() : super(PortfolioData.initial()) {
    _load();
  }

  static const _prefsKey = 'portfolioData';
  static const int vacantLotCost = 20;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      state = PortfolioData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt or incompatible old save data -- keep the fresh initial
      // state rather than crash the app on launch.
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  void addCurrency(int amount) {
    if (amount == 0) return;
    state = state.copyWith(currency: state.currency + amount);
    _save();
  }

  void addXp(int amount) {
    if (amount == 0) return;
    state = state.copyWith(totalXp: state.totalXp + amount);
    _save();
  }

  // Awards a property tile at a specific slot. Never downgrades: if the
  // slot already holds an equal-or-better tier, this is a no-op.
  void awardPropertyTile(String neighborhoodId, int slotIndex, PropertyTier tier) {
    final slots = state.neighborhoodSlots[neighborhoodId];
    if (slots == null || slotIndex < 0 || slotIndex >= slots.length) return;
    if (tier.index <= slots[slotIndex].index) return;

    final newSlots = Map<String, List<PropertyTier>>.from(state.neighborhoodSlots);
    final updated = List<PropertyTier>.from(slots);
    updated[slotIndex] = tier;
    newSlots[neighborhoodId] = updated;

    state = state.copyWith(neighborhoodSlots: newSlots);
    _save();
  }

  // Awards a tier to the first empty slot in a neighborhood. Used by
  // modes that just need "give the player a property" without picking a
  // specific slot (e.g. Daily Estate Challenge results).
  void awardToFirstEmptySlot(String neighborhoodId, PropertyTier tier) {
    final slots = state.neighborhoodSlots[neighborhoodId];
    if (slots == null) return;
    final emptyIndex = slots.indexWhere((t) => !t.isOwned);
    if (emptyIndex == -1) return;
    awardPropertyTile(neighborhoodId, emptyIndex, tier);
  }

  // Spends currency to fill one empty slot with a Vacant Lot -- lets
  // Time Attack/Theme Rush/Infinite currency meaningfully progress a
  // neighborhood the player hasn't had a great Daily Challenge run in.
  bool fillEmptySlotWithCurrency(String neighborhoodId) {
    final slots = state.neighborhoodSlots[neighborhoodId];
    if (slots == null) return false;
    final emptyIndex = slots.indexWhere((t) => !t.isOwned);
    if (emptyIndex == -1 || state.currency < vacantLotCost) return false;

    final newSlots = Map<String, List<PropertyTier>>.from(state.neighborhoodSlots);
    final updated = List<PropertyTier>.from(slots);
    updated[emptyIndex] = PropertyTier.vacantLot;
    newSlots[neighborhoodId] = updated;

    state = state.copyWith(
      currency: state.currency - vacantLotCost,
      neighborhoodSlots: newSlots,
    );
    _save();
    return true;
  }
}

final portfolioProvider = StateNotifierProvider<PortfolioController, PortfolioData>((ref) {
  return PortfolioController();
});
