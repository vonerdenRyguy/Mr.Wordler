import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mode_stats_data.dart';

class ModeStatsController extends StateNotifier<ModeStatsData> {
  ModeStatsController() : super(ModeStatsData.initial()) {
    _load();
  }

  static const _prefsKey = 'modeStatsData';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      state = ModeStatsData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt/old save data -- keep the fresh initial state.
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  // Returns true if this was a new high score.
  bool reportInfiniteEstateScore(int score) {
    if (score <= state.infiniteEstateHighScore) return false;
    state = state.copyWith(infiniteEstateHighScore: score);
    _save();
    return true;
  }

  // Returns true if this was a new personal best for the theme.
  bool reportThemeRushTime(String themeId, int seconds) {
    final current = state.themeRushBestSeconds[themeId];
    if (current != null && seconds >= current) return false;
    final updated = Map<String, int>.from(state.themeRushBestSeconds);
    updated[themeId] = seconds;
    state = state.copyWith(themeRushBestSeconds: updated);
    _save();
    return true;
  }
}

final modeStatsProvider = StateNotifierProvider<ModeStatsController, ModeStatsData>((ref) {
  return ModeStatsController();
});
