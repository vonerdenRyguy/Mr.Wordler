import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../explore/island_map.dart';
import '../players/players.dart';

// Everything needed to resume a village exactly where it was left: the
// board/rack/pool (so structures can be re-derived and play continues
// seamlessly), lastCashedOutScore -- the score value already paid out as
// currency/XP, so ending a session again without having grown the
// village in between awards nothing extra -- and reachedLandmarks (kept for
// backwards compat; superseded by foundSpecials in v3).
//
// spec-15 (saveVersion 3) adds fog, island map identity, and explore state:
//   mapSeed / mapVersion — which island map this save belongs to.
//   cleared             — base64 FogMap bit set.
//   everUsed            — board cells that have ever held a letter.
//   foundSpecials       — special tile IDs already activated.
//   shrines             — shrine kinds unlocked.
//   levelTreats         — XP levels at which treats have been claimed.
class VillageSaveData {
  final List<String?> boardCells;
  final List<String?> rackCells;
  final List<String> pool;
  final List<String> dealtLetters;
  final int lastCashedOutScore;
  final Set<int> reachedLandmarks; // kept; no longer shown as landmark stars (spec-15 commit 8)
  final Set<String> discoveredWords;
  // Format version. 1 = original 21-letter rack; 2 = 10-letter rack;
  // 3 = explore (fog + island map + XP tracking). See village_save_migration.dart.
  final int saveVersion;

  // ── spec-15 explore fields ───────────────────────────────────────────────

  /// Seed that identifies the island map (same for all players; spec-17 may
  /// change this to a family map).
  final int mapSeed;

  /// Incremented when the map layout changes (spec-17 family island).
  final int mapVersion;

  /// base64-encoded [FogMap]. Null for a brand-new village (fog computed on
  /// first load from [boardCells]).
  final String? cleared;

  /// Board cell indices that have ever held a letter. Prevents XP farming.
  final Set<int> everUsed;

  /// Every valid word the player has ever placed on the board. Used by the
  /// XP formula to decide the word-discovery bonus (+5 for a new word).
  final Set<String> everWords;

  /// Special tile IDs (e.g. 's3') that the player has activated.
  final Set<String> foundSpecials;

  /// Shrine kinds the player has unlocked.
  final Set<ShrineKind> shrines;

  /// XP levels at which the level-up treat has already been claimed.
  final Set<int> levelTreats;

  static const int currentVersion = 3;

  /// The fixed seed for the spec-15 island map.
  static const int kDefaultMapSeed = 15001;
  static const int kDefaultMapVersion = 1;

  const VillageSaveData({
    required this.boardCells,
    required this.rackCells,
    required this.pool,
    required this.dealtLetters,
    required this.lastCashedOutScore,
    this.reachedLandmarks = const {},
    this.discoveredWords = const {},
    this.saveVersion = currentVersion,
    this.mapSeed = kDefaultMapSeed,
    this.mapVersion = kDefaultMapVersion,
    this.cleared,
    this.everUsed = const {},
    this.everWords = const {},
    this.foundSpecials = const {},
    this.shrines = const {},
    this.levelTreats = const {},
  });

  Map<String, dynamic> toJson() => {
        'boardCells': boardCells,
        'rackCells': rackCells,
        'pool': pool,
        'dealtLetters': dealtLetters,
        'lastCashedOutScore': lastCashedOutScore,
        'reachedLandmarks': reachedLandmarks.toList(),
        'discoveredWords': discoveredWords.toList(),
        'saveVersion': saveVersion,
        // spec-15 fields
        'mapSeed': mapSeed,
        'mapVersion': mapVersion,
        if (cleared != null) 'cleared': cleared,
        'everUsed': everUsed.toList(),
        'everWords': everWords.toList(),
        'foundSpecials': foundSpecials.toList(),
        'shrines': shrines.map((s) => s.name).toList(),
        'levelTreats': levelTreats.toList(),
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
        saveVersion: json['saveVersion'] as int? ?? 1,
        // spec-15 fields — absent on v1/v2 saves; migration handles them
        mapSeed: json['mapSeed'] as int? ?? kDefaultMapSeed,
        mapVersion: json['mapVersion'] as int? ?? kDefaultMapVersion,
        cleared: json['cleared'] as String?,
        everUsed: (json['everUsed'] as List?)?.map((e) => e as int).toSet() ?? const {},
        everWords: (json['everWords'] as List?)?.map((e) => e as String).toSet() ?? const {},
        foundSpecials:
            (json['foundSpecials'] as List?)?.map((e) => e as String).toSet() ?? const {},
        shrines: (json['shrines'] as List?)
                ?.map((e) => ShrineKind.values.byName(e as String))
                .toSet() ??
            const {},
        levelTreats: (json['levelTreats'] as List?)?.map((e) => e as int).toSet() ?? const {},
      );
}

// Persists the Infinite Estate village as a single JSON blob via
// shared_preferences, matching the app's existing local-storage pattern.
class VillageSaveController {
  /// [prefix] picks whose village: by default the player holding the
  /// phone; pass another player's prefix to look at theirs.
  VillageSaveController({String? prefix}) : _key = '${prefix ?? PlayerKeys.prefix}infiniteEstateVillageSave';

  final String _key;

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
