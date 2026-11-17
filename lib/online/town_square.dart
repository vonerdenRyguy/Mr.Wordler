import 'dart:math';

import '../daily/daily_seed.dart' show dailyDateKey;

// The Town Square (spec-13): an online family builds one shared building at
// a time, brick by brick, from playing as usual. When nothing is being
// built, the family votes on what comes next.
//
// Saved on the server as families/{fid}/square/state and changed only in a
// transaction (FamilyBackend.changeSquare) with the pure functions below, so
// two phones adding bricks at once never lose any.

/// A building the family can put up in the Town Square.
class SquareBuilding {
  const SquareBuilding(this.id, this.name, this.color);

  final String id;
  final String name;

  /// Its main color (drawn in code for now; real art later).
  final int color;
}

const kSquareBuildings = [
  SquareBuilding('fountain', 'Fountain', 0xFF4A90C8),
  SquareBuilding('bandstand', 'Bandstand', 0xFFC8553D),
  SquareBuilding('library', 'Library', 0xFF7A5C3E),
  SquareBuilding('garden', 'Garden', 0xFF4C9A52),
  SquareBuilding('clocktower', 'Clock tower', 0xFF8C7A9B),
  SquareBuilding('bakery', 'Bakery', 0xFFD9A441),
];

SquareBuilding? squareBuilding(String? id) => kSquareBuildings.where((b) => b.id == id).firstOrNull;

/// Bricks for things the family does anyway.
const kBricksDaily = 3;
const kBricksFamilyWord = 5;
const kBricksNewBuilding = 2;
const kBricksHelp = 1;

/// The most one change may add (the server's rules say the same).
const kMaxBricksAtOnce = 5;

/// Coins each when a building is finished.
const kSquareCoins = 15;

/// For a phone check with a small goal:
/// `flutter build apk --debug --dart-define=SQUARE_TEST_GOAL=6`.
const _testGoal = int.fromEnvironment('SQUARE_TEST_GOAL');

/// About 15 bricks per member, at least 30.
int squareGoal(int members) => _testGoal > 0 ? _testGoal : max(30, 15 * members);

/// The week a vote belongs to: the date key of that week's Monday (UTC).
String squareWeekKey(DateTime now) {
  final utc = now.toUtc();
  final day = DateTime.utc(utc.year, utc.month, utc.day);
  return dailyDateKey(day.subtract(Duration(days: day.weekday - DateTime.monday)));
}

class SquareVote {
  const SquareVote({required this.week, required this.choices, this.picks = const {}, this.firstPick = const {}});

  final String week;

  /// Three building ids.
  final List<String> choices;

  /// uid -> the building they picked.
  final Map<String, String> picks;

  /// building id -> when it was first picked (ms), for breaking a tie.
  final Map<String, int> firstPick;

  int votesFor(String id) => picks.values.where((p) => p == id).length;

  /// Most votes wins; a tie goes to the one picked first; with no votes,
  /// the first choice.
  String get winner {
    var best = choices.first;
    var bestVotes = -1;
    var bestTime = 0;
    for (final id in choices) {
      final votes = votesFor(id);
      if (votes == 0 && bestVotes >= 0) continue;
      final time = firstPick[id] ?? 0;
      if (votes > bestVotes || (votes == bestVotes && votes > 0 && time < bestTime)) {
        best = id;
        bestVotes = votes;
        bestTime = time;
      }
    }
    return best;
  }

  Map<String, Object?> toData() => {'week': week, 'choices': choices, 'picks': picks, 'firstPick': firstPick};

  static SquareVote? fromData(Object? raw) {
    if (raw is! Map) return null;
    final week = raw['week'];
    final choices = [
      for (final c in (raw['choices'] as List? ?? const []))
        if (c is String) c
    ];
    if (week is! String || choices.isEmpty) return null;
    return SquareVote(
      week: week,
      choices: choices,
      picks: {
        for (final e in (raw['picks'] as Map? ?? const {}).entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
      },
      firstPick: {
        for (final e in (raw['firstPick'] as Map? ?? const {}).entries)
          if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt(),
      },
    );
  }
}

class BuiltThing {
  const BuiltThing(this.id, this.on);

  final String id;

  /// The UTC day it was finished.
  final String on;
}

class TownSquare {
  const TownSquare({
    this.building,
    this.bricks = 0,
    this.spent = 0,
    this.goal = 30,
    this.built = const [],
    this.vote,
    this.finishedOn,
  });

  /// What's being built now; null while the family votes.
  final String? building;

  /// Every brick the family has ever added (only goes up).
  final int bricks;

  /// Bricks used by finished buildings (only goes up).
  final int spent;

  final int goal;
  final List<BuiltThing> built;
  final SquareVote? vote;

  /// The day the last building was finished.
  final String? finishedOn;

  /// Bricks toward the current (or next) building.
  int get progress => max(0, bricks - spent);

  bool get voting => building == null;

  TownSquare copyWith({
    String? building,
    bool clearBuilding = false,
    int? bricks,
    int? spent,
    int? goal,
    List<BuiltThing>? built,
    SquareVote? vote,
    bool clearVote = false,
    String? finishedOn,
  }) =>
      TownSquare(
        building: clearBuilding ? null : (building ?? this.building),
        bricks: bricks ?? this.bricks,
        spent: spent ?? this.spent,
        goal: goal ?? this.goal,
        built: built ?? this.built,
        vote: clearVote ? null : (vote ?? this.vote),
        finishedOn: finishedOn ?? this.finishedOn,
      );

  Map<String, Object?> toData() => {
        'building': building,
        'bricks': bricks,
        'spent': spent,
        'goal': goal,
        'built': [
          for (final b in built) {'id': b.id, 'on': b.on}
        ],
        'vote': vote?.toData(),
        'finishedOn': finishedOn,
      };

  static TownSquare fromData(Map<String, Object?>? d) {
    if (d == null) return const TownSquare();
    int n(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return TownSquare(
      building: d['building'] as String?,
      bricks: n(d['bricks'], 0),
      spent: n(d['spent'], 0),
      goal: n(d['goal'], 30),
      built: [
        for (final b in (d['built'] as List? ?? const []))
          if (b is Map && b['id'] is String) BuiltThing(b['id'] as String, b['on'] as String? ?? ''),
      ],
      vote: SquareVote.fromData(d['vote']),
      finishedOn: d['finishedOn'] as String?,
    );
  }
}

/// Three buildings for a vote: the ones built the fewest times, in catalog
/// order (so the first vote is always Fountain, Bandstand, Library).
List<String> voteChoices(List<BuiltThing> built) {
  int times(String id) => built.where((b) => b.id == id).length;
  final order = [...kSquareBuildings]..sort((a, b) {
      final c = times(a.id).compareTo(times(b.id));
      return c != 0 ? c : kSquareBuildings.indexOf(a).compareTo(kSquareBuildings.indexOf(b));
    });
  return [for (final b in order.take(3)) b.id];
}

/// Opens a vote when nothing is being built, closes it when everyone has
/// voted or its week is over, and finishes the building when the bar is
/// full. Every change to the square ends with this.
TownSquare settleSquare(TownSquare s, {required List<String> memberUids, required DateTime now}) {
  var out = s;
  if (out.building == null && out.vote == null) {
    out = out.copyWith(vote: SquareVote(week: squareWeekKey(now), choices: voteChoices(out.built)));
  }
  final vote = out.vote;
  if (out.building == null && vote != null) {
    final everyone = memberUids.isNotEmpty && memberUids.every(vote.picks.containsKey);
    if (everyone || vote.week != squareWeekKey(now)) {
      out = out.copyWith(building: vote.winner, goal: squareGoal(memberUids.length), clearVote: true);
    }
  }
  final building = out.building;
  if (building != null && out.progress >= out.goal) {
    final day = dailyDateKey(now);
    out = out.copyWith(
      built: [...out.built, BuiltThing(building, day)],
      spent: out.spent + out.goal,
      clearBuilding: true,
      finishedOn: day,
    );
    out = out.copyWith(vote: SquareVote(week: squareWeekKey(now), choices: voteChoices(out.built)));
  }
  return out;
}

/// Adds [count] bricks (at most kMaxBricksAtOnce).
TownSquare addSquareBricks(TownSquare s, int count, {required List<String> memberUids, required DateTime now}) =>
    settleSquare(s.copyWith(bricks: s.bricks + count.clamp(0, kMaxBricksAtOnce)), memberUids: memberUids, now: now);

/// [uid] votes for [id] (changing their mind is fine). Nothing happens if
/// there's no vote open or [id] isn't one of its choices.
TownSquare pickSquareBuilding(TownSquare s, String uid, String id,
    {required List<String> memberUids, required DateTime now}) {
  final opened = settleSquare(s, memberUids: memberUids, now: now);
  final vote = opened.vote;
  if (opened.building != null || vote == null || !vote.choices.contains(id)) return opened;
  final picked = SquareVote(
    week: vote.week,
    choices: vote.choices,
    picks: {...vote.picks, uid: id},
    firstPick: {...vote.firstPick, if (!vote.firstPick.containsKey(id)) id: now.millisecondsSinceEpoch},
  );
  return settleSquare(opened.copyWith(vote: picked), memberUids: memberUids, now: now);
}
