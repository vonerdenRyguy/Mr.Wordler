import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../portfolio/neighborhood.dart';
import '../portfolio/portfolio_controller.dart';
import '../portfolio/portfolio_data.dart';
import '../portfolio/property_tier.dart';
import 'daily_challenge_data.dart';
import 'daily_seed.dart';

class DailyChallengeController extends StateNotifier<DailyChallengeData> {
  DailyChallengeController() : super(DailyChallengeData.initial()) {
    _load();
  }

  static const _prefsKey = 'dailyChallengeData';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      state = DailyChallengeData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt/old save data -- keep the fresh initial state.
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  bool hasPlayedToday(DateTime now) => state.lastPlayedDateKey == dailyDateKey(now);

  // Records today's attempt (win or give-up) and updates the streak.
  // Playing "today" more than once is prevented by the caller checking
  // hasPlayedToday before ever starting a round, not by this method.
  void recordAttempt({
    required DateTime now,
    required bool completed,
    required int timeSeconds,
    required bool bonusWordFound,
    required PropertyTier tierAwarded,
  }) {
    final todayKey = dailyDateKey(now);
    final continuesStreak = completed && isConsecutiveDay(state.lastPlayedDateKey, now);
    final newStreak = completed ? (continuesStreak ? state.streak + 1 : 1) : 0;

    state = state.copyWith(
      lastPlayedDateKey: todayKey,
      streak: newStreak,
      completions: completed ? state.completions + 1 : state.completions,
      totalCompletionSeconds:
          completed ? state.totalCompletionSeconds + timeSeconds : state.totalCompletionSeconds,
      bonusWordsFound: (completed && bonusWordFound) ? state.bonusWordsFound + 1 : state.bonusWordsFound,
      lastResult: DailyResult(
        dateKey: todayKey,
        completed: completed,
        timeSeconds: timeSeconds,
        bonusWordFound: bonusWordFound,
        tierAwarded: tierAwarded,
      ),
    );
    _save();
  }
}

final dailyChallengeProvider =
    StateNotifierProvider<DailyChallengeController, DailyChallengeData>((ref) {
  return DailyChallengeController();
});

// Picks which neighborhood/slot a Daily Challenge tile goes to: the first
// empty slot found (in neighborhood order), or -- once every slot is
// filled -- the current weakest slot, but only if the new tier actually
// beats it. Kept outside PortfolioController since it's Daily-Challenge-
// specific placement policy, not a general Portfolio operation.
void awardDailyTileToPortfolio(
  PortfolioController controller,
  PortfolioData portfolio,
  PropertyTier tier,
) {
  if (tier == PropertyTier.empty) return;

  for (final n in kNeighborhoods) {
    final slots = portfolio.neighborhoodSlots[n.id];
    if (slots == null) continue;
    final emptyIndex = slots.indexWhere((t) => !t.isOwned);
    if (emptyIndex != -1) {
      controller.awardPropertyTile(n.id, emptyIndex, tier);
      return;
    }
  }

  String? weakestNeighborhoodId;
  int weakestSlotIndex = -1;
  PropertyTier weakestTier = PropertyTier.mansion;
  for (final n in kNeighborhoods) {
    final slots = portfolio.neighborhoodSlots[n.id];
    if (slots == null) continue;
    for (int i = 0; i < slots.length; i++) {
      if (slots[i].index < weakestTier.index) {
        weakestTier = slots[i];
        weakestNeighborhoodId = n.id;
        weakestSlotIndex = i;
      }
    }
  }
  if (weakestNeighborhoodId != null && tier.index > weakestTier.index) {
    controller.awardPropertyTile(weakestNeighborhoodId, weakestSlotIndex, tier);
  }
}
