import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../explore/island_map.dart';
import '../game/word_runs.dart' show WordRun;
import '../players/players.dart';
import '../villagers/village_book.dart';

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
//
// spec-16 (saveVersion 4) adds villagers:
//   villagers           — the villagers who have moved in (name, hearts, wish).
//
// spec-17 (saveVersion 5) real words only:
//   tidiedLoose         — loose letters (not in a real word) have been sent
//                         back to the rack once for this old village.
//   looseNote           — how many letters Mr. W put back; shown once on the
//                         next visit, then 0.
//   bag                 — the letter bag: letters that don't fit the 10-letter
//                         rack wait here (optional; absent = empty).
//   keptRuns            — words already standing when the real-words rule
//                         arrived; their buildings stay until a letter moves
//                         (optional; absent = none).
//
// spec-18 (saveVersion 6) Letterra:
//   planet              — {slot, migratedFrom}: the harbor spot this village
//                         sits on and, for a moved village, the old version.
class VillageSaveData {
  final List<String?> boardCells;
  final List<String?> rackCells;
  final List<String> pool;
  final List<String> dealtLetters;
  final int lastCashedOutScore;
  final Set<int> reachedLandmarks; // kept; no longer shown as landmark stars (spec-15 commit 8)
  final Set<String> discoveredWords;
  // Format version. 1 = original 21-letter rack; 2 = 10-letter rack;
  // 3 = explore (fog + island map + XP tracking); 4 = villagers;
  // 5 = real words only (tidiedLoose, looseNote); 6 = Letterra (planet).
  // See village_save_migration.dart.
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

  /// spec-16: the villagers who have moved in.
  final VillagerBook villagers;

  /// spec-17: the one-time tidy of an old village has happened.
  final bool tidiedLoose;

  /// spec-17: letters put back in the rack that the player hasn't been told
  /// about yet.
  final int looseNote;

  /// spec-17 letter bag.
  final List<String> bag;

  /// spec-17: words that stood on the board when the rule arrived (see
  /// `settle`'s `kept`).
  final List<WordRun> keptRuns;


  /// spec-18: the harbor spot (0..7) this village sits on. Null on a save
  /// that hasn't been moved onto Letterra yet.
  final int? planetSlot;

  /// spec-18: the save version this village was moved from, or null when it
  /// was born on Letterra.
  final int? migratedFrom;

  /// spec-18b: this village began on an empty shore with a gold star, and
  /// whether its first word has covered it. Absent on every older save.
  final bool starStart;
  final bool starDone;

  /// No word counts yet except one that covers the star.
  bool get starActive => starStart && !starDone;

  /// spec-18b: regions already celebrated; null = fill quietly from the fog.
  final Set<int>? bandsReached;

  static const int currentVersion = 6;

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
    this.villagers = const VillagerBook(),
    this.tidiedLoose = false,
    this.looseNote = 0,
    this.bag = const [],
    this.keptRuns = const [],
    this.planetSlot,
    this.migratedFrom,
    this.starStart = false,
    this.starDone = false,
    this.bandsReached,
  });

  VillageSaveData copyWith({
    int? saveVersion,
    VillagerBook? villagers,
    List<String?>? boardCells,
    List<String>? pool,
    List<String>? dealtLetters,
    String? cleared,
    Set<int>? everUsed,
    int? planetSlot,
    int? migratedFrom,
    List<WordRun>? keptRuns,
  }) =>
      VillageSaveData(
        boardCells: boardCells ?? this.boardCells,
        rackCells: rackCells,
        pool: pool ?? this.pool,
        dealtLetters: dealtLetters ?? this.dealtLetters,
        lastCashedOutScore: lastCashedOutScore,
        reachedLandmarks: reachedLandmarks,
        discoveredWords: discoveredWords,
        saveVersion: saveVersion ?? this.saveVersion,
        mapSeed: mapSeed,
        mapVersion: mapVersion,
        cleared: cleared ?? this.cleared,
        everUsed: everUsed ?? this.everUsed,
        everWords: everWords,
        foundSpecials: foundSpecials,
        shrines: shrines,
        levelTreats: levelTreats,
        villagers: villagers ?? this.villagers,
        tidiedLoose: tidiedLoose,
        looseNote: looseNote,
        bag: bag,
        keptRuns: keptRuns ?? this.keptRuns,
        planetSlot: planetSlot ?? this.planetSlot,
        migratedFrom: migratedFrom ?? this.migratedFrom,
        starStart: starStart,
        starDone: starDone,
        bandsReached: bandsReached,
      );

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
        // spec-16
        'villagers': villagers.toJson(),
        // spec-17
        'tidiedLoose': tidiedLoose,
        'looseNote': looseNote,
        if (bag.isNotEmpty) 'bag': bag,
        if (keptRuns.isNotEmpty)
          'keptRuns': [
            for (final r in keptRuns) {'w': r.word, 'p': r.positions, 'a': r.across},
          ],
        // spec-18
        if (planetSlot != null)
          'planet': {
            'slot': planetSlot,
            if (migratedFrom != null) 'migratedFrom': migratedFrom,
          },
        // spec-18b
        if (starStart) 'starStart': true,
        if (starDone) 'starDone': true,
        if (bandsReached != null) 'bandsReached': bandsReached!.toList(),
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
        villagers: VillagerBook.fromJson(json['villagers']),
        tidiedLoose: json['tidiedLoose'] as bool? ?? false,
        looseNote: json['looseNote'] as int? ?? 0,
        bag: (json['bag'] as List?)?.cast<String>() ?? const [],
        keptRuns: [
          for (final r in (json['keptRuns'] as List?) ?? const [])
            WordRun(
              (r as Map)['w'] as String,
              (r['p'] as List).cast<int>(),
              r['a'] as bool? ?? true,
            ),
        ],
        planetSlot: (json['planet'] as Map?)?['slot'] as int?,
        migratedFrom: (json['planet'] as Map?)?['migratedFrom'] as int?,
        starStart: json['starStart'] as bool? ?? false,
        starDone: json['starDone'] as bool? ?? false,
        bandsReached: (json['bandsReached'] as List?)?.map((e) => e as int).toSet(),
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
