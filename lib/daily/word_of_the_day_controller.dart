import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../players/players.dart';
import 'daily_seed.dart';

/// Coins for spelling the Word of the day in your village, once a day.
const int kWordOfDayCoins = 10;

// Remembers the last day the Word of the day reward was claimed. The state
// is that day's date key (see dailyDateKey), or null if never claimed.
// Saved under `wordOfDayData` as {"claimedDateKey": "2026-11-14"}.
class WordOfDayController extends StateNotifier<String?> {
  WordOfDayController() : super(null) {
    _loaded = _load();
  }

  final String _prefsKey = PlayerKeys.of('wordOfDayData');
  late final Future<void> _loaded;

  /// Completes once the saved value has been read.
  Future<void> get loaded => _loaded;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final saved = (jsonDecode(raw) as Map<String, dynamic>)['claimedDateKey'] as String?;
      // Don't overwrite a claim made while this was loading.
      if (mounted && state == null) state = saved;
    } catch (_) {
      // Corrupt data -- treat it as never claimed.
    }
  }

  bool claimedToday(DateTime now) => state == dailyDateKey(now);

  /// Marks today's reward as claimed. True only the first time today; the
  /// caller pays the coins on true.
  bool claim(DateTime now) {
    if (claimedToday(now)) return false;
    state = dailyDateKey(now);
    _save();
    return true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({'claimedDateKey': state}));
  }
}

final wordOfDayProvider = StateNotifierProvider<WordOfDayController, String?>((ref) {
  ref.watch(currentPlayerIdProvider);
  return WordOfDayController();
});
