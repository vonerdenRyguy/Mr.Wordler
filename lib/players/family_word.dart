import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../daily/daily_seed.dart';
import '../daily/word_of_the_day.dart';

// The family word (spec-07): one hidden word a day for everyone on this
// phone, with its meaning as the hint. Each player who finishes their
// Daily uncovers a share of its letters, sized so that once everyone has
// played the whole word is showing. Anyone may guess it sooner.
//
// It is the one piece of saved data that belongs to the whole phone
// rather than to a player (key `familyWordData`).

/// Coins each player gets when the family guesses the word before all its
/// letters are out, and when it uncovers itself.
const int kFamilyWordEarlyCoins = 20;
const int kFamilyWordCoins = 10;

/// Today's family word: taken from the Word of the day list, half a list
/// away from today's Word of the day so the two are never the same word.
WordOfDay familyWordFor(DateTime date, List<WordOfDay> list) =>
    list[(dayNumber(date) + list.length ~/ 2) % list.length];

/// The order the word's letters are uncovered in: the same for everyone on
/// a given day, and not simply left to right.
List<int> familyRevealOrder(String word, DateTime date) =>
    [for (int i = 0; i < word.length; i++) i]..shuffle(Random(dailySeedForDate(date) + 7));

class FamilyWordData {
  const FamilyWordData({
    this.dateKey,
    this.found = const {},
    this.solved = false,
    this.solvedEarly = false,
    this.owed = const {},
    this.streak = 0,
    this.lastSolvedDateKey,
    this.total = 0,
  });

  /// The day [found] and [solved] are about.
  final String? dateKey;

  /// Letter positions uncovered today, by the id of the player who found
  /// them. Insertion order = the order the players finished.
  final Map<String, List<int>> found;
  final bool solved;
  final bool solvedEarly;

  /// Coins waiting for each player, paid the next time they hold the phone.
  final Map<String, int> owed;

  /// Days in a row the word was found, the last such day, and the count.
  final int streak;
  final String? lastSolvedDateKey;
  final int total;

  Set<int> get revealed => {for (final list in found.values) ...list};

  /// Who found the letter at [index], or null.
  String? finderOf(int index) {
    for (final entry in found.entries) {
      if (entry.value.contains(index)) return entry.key;
    }
    return null;
  }

  FamilyWordData copyWith({
    String? dateKey,
    Map<String, List<int>>? found,
    bool? solved,
    bool? solvedEarly,
    Map<String, int>? owed,
    int? streak,
    String? lastSolvedDateKey,
    int? total,
  }) =>
      FamilyWordData(
        dateKey: dateKey ?? this.dateKey,
        found: found ?? this.found,
        solved: solved ?? this.solved,
        solvedEarly: solvedEarly ?? this.solvedEarly,
        owed: owed ?? this.owed,
        streak: streak ?? this.streak,
        lastSolvedDateKey: lastSolvedDateKey ?? this.lastSolvedDateKey,
        total: total ?? this.total,
      );

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'found': found,
        'solved': solved,
        'solvedEarly': solvedEarly,
        'owed': owed,
        'streak': streak,
        'lastSolvedDateKey': lastSolvedDateKey,
        'total': total,
      };

  factory FamilyWordData.fromJson(Map<String, dynamic> json) => FamilyWordData(
        dateKey: json['dateKey'] as String?,
        found: {
          for (final e in (json['found'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: [for (final i in e.value as List) i as int],
        },
        solved: json['solved'] as bool? ?? false,
        solvedEarly: json['solvedEarly'] as bool? ?? false,
        owed: {
          for (final e in (json['owed'] as Map<String, dynamic>? ?? const {}).entries) e.key: e.value as int,
        },
        streak: json['streak'] as int? ?? 0,
        lastSolvedDateKey: json['lastSolvedDateKey'] as String?,
        total: json['total'] as int? ?? 0,
      );
}

class FamilyWordController extends StateNotifier<FamilyWordData> {
  FamilyWordController() : super(const FamilyWordData()) {
    _ready = _load();
  }

  static const prefsKey = 'familyWordData';
  late final Future<void> _ready;

  /// Completes once the saved value has been read.
  Future<void> get ready => _ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || !mounted) return;
    try {
      state = FamilyWordData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt data -- start again.
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(state.toJson()));
  }

  /// Today's view of the data: yesterday's letters don't carry over, but
  /// owed coins, the streak and the total do.
  FamilyWordData today(DateTime now) {
    final key = dailyDateKey(now);
    if (state.dateKey == key) return state;
    return FamilyWordData(
      dateKey: key,
      owed: state.owed,
      streak: state.streak,
      lastSolvedDateKey: state.lastSolvedDateKey,
      total: state.total,
    );
  }

  /// [playerId] finished today's Daily: uncover their share of [word].
  /// Returns the positions they found (empty if they had already played,
  /// or the word was already found).
  List<int> recordPlayed({
    required String playerId,
    required DateTime now,
    required String word,
    required List<String> playerIds,
  }) {
    var data = today(now);
    if (data.solved || data.found.containsKey(playerId)) return const [];
    final hidden = [
      for (final i in familyRevealOrder(word, now))
        if (!data.revealed.contains(i)) i,
    ];
    // Shared out between everyone still to play, this player included, so
    // the last one always uncovers whatever is left.
    final stillToPlay = playerIds.where((id) => !data.found.containsKey(id)).length.clamp(1, playerIds.length);
    final share = hidden.take((hidden.length / stillToPlay).ceil()).toList();
    data = data.copyWith(found: {...data.found, playerId: share});
    state = data;
    if (data.revealed.length >= word.length) {
      _solve(now: now, early: false, playerIds: playerIds);
    } else {
      _save();
    }
    return share;
  }

  /// A guess at the word. Right = the family has found it early.
  bool guess({
    required String text,
    required DateTime now,
    required String word,
    required List<String> playerIds,
  }) {
    final data = today(now);
    if (data.solved) return true;
    if (text.trim().toUpperCase() != word.toUpperCase()) return false;
    state = data;
    _solve(now: now, early: true, playerIds: playerIds);
    return true;
  }

  void _solve({required DateTime now, required bool early, required List<String> playerIds}) {
    final key = dailyDateKey(now);
    final coins = early ? kFamilyWordEarlyCoins : kFamilyWordCoins;
    state = state.copyWith(
      solved: true,
      solvedEarly: early,
      // Everyone on the phone, whether or not they have played today.
      owed: {
        ...state.owed,
        for (final id in playerIds) id: (state.owed[id] ?? 0) + coins,
      },
      streak: isConsecutiveDay(state.lastSolvedDateKey, now) ? state.streak + 1 : 1,
      lastSolvedDateKey: key,
      total: state.total + 1,
    );
    _save();
  }

  /// Takes the coins waiting for [playerId] (0 if none); the caller adds
  /// them to that player's Portfolio.
  int claimOwed(String playerId) {
    final coins = state.owed[playerId] ?? 0;
    if (coins == 0) return 0;
    state = state.copyWith(owed: {...state.owed}..remove(playerId));
    _save();
    return coins;
  }
}

final familyWordProvider = StateNotifierProvider<FamilyWordController, FamilyWordData>((ref) => FamilyWordController());
