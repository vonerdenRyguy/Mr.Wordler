import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Free Play's "Top times". Entries are stored (in game_screen.dart's
// winDialog) under 'leaderboardEntries' as JSON objects:
// {"name": ..., "time": <seconds as int>, "displayTime": "MM:SS"}.
// Returned fastest first.
Future<List<Map<String, dynamic>>> loadLeaderboardEntries() async {
  final prefs = await SharedPreferences.getInstance();
  final entries = prefs.getStringList('leaderboardEntries') ?? [];

  final parsedEntries = <Map<String, dynamic>>[];
  for (final entry in entries) {
    try {
      parsedEntries.add(Map<String, dynamic>.from(jsonDecode(entry) as Map<String, dynamic>));
    } catch (_) {
      // Skip a malformed entry rather than lose the whole list.
    }
  }
  parsedEntries.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
  return parsedEntries;
}
