import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Everything needed to resume a village exactly where it was left: the
// board/rack/pool (so structures can be re-derived and play continues
// seamlessly), lastCashedOutScore -- the score value already paid out as
// currency/XP, so ending a session again without having grown the
// village in between awards nothing extra -- and reachedLandmarks, so a
// landmark's one-time event never fires twice.
class VillageSaveData {
  final List<String?> boardCells;
  final List<String?> rackCells;
  final List<String> pool;
  final List<String> dealtLetters;
  final int lastCashedOutScore;
  final Set<int> reachedLandmarks;
  final Set<String> discoveredWords;

  const VillageSaveData({
    required this.boardCells,
    required this.rackCells,
    required this.pool,
    required this.dealtLetters,
    required this.lastCashedOutScore,
    this.reachedLandmarks = const {},
    this.discoveredWords = const {},
  });

  Map<String, dynamic> toJson() => {
        'boardCells': boardCells,
        'rackCells': rackCells,
        'pool': pool,
        'dealtLetters': dealtLetters,
        'lastCashedOutScore': lastCashedOutScore,
        'reachedLandmarks': reachedLandmarks.toList(),
        'discoveredWords': discoveredWords.toList(),
      };

  factory VillageSaveData.fromJson(Map<String, dynamic> json) => VillageSaveData(
        boardCells: (json['boardCells'] as List).map((e) => e as String?).toList(),
        rackCells: (json['rackCells'] as List).map((e) => e as String?).toList(),
        pool: (json['pool'] as List).cast<String>(),
        dealtLetters: (json['dealtLetters'] as List).cast<String>(),
        lastCashedOutScore: json['lastCashedOutScore'] as int? ?? 0,
        reachedLandmarks:
            (json['reachedLandmarks'] as List?)?.map((e) => e as int).toSet() ?? const {},
        discoveredWords:
            (json['discoveredWords'] as List?)?.map((e) => e as String).toSet() ?? const {},
      );
}

// Persists the Infinite Estate village as a single JSON blob via
// shared_preferences, matching the app's existing local-storage pattern.
class VillageSaveController {
  static const _key = 'infiniteEstateVillageSave';

  Future<VillageSaveData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return VillageSaveData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt/old save data -- treat as "no save" rather than crash.
      return null;
    }
  }

  Future<void> save(VillageSaveData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
  }
}
