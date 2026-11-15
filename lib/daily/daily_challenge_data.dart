import '../portfolio/property_tier.dart';

// Result of a single day's attempt, kept so the "already played today"
// screen and (later) the share card can show what happened without
// re-deriving it.
class DailyResult {
  final String dateKey;
  final bool completed;
  final int timeSeconds;
  final bool bonusWordFound;
  final PropertyTier tierAwarded;

  // spec-05. Null/0 on a result saved by an older build.
  final String? themeName;
  final String? secretWord; // uppercase
  final int cluesUsed;

  const DailyResult({
    required this.dateKey,
    required this.completed,
    required this.timeSeconds,
    required this.bonusWordFound,
    required this.tierAwarded,
    this.themeName,
    this.secretWord,
    this.cluesUsed = 0,
  });

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'completed': completed,
        'timeSeconds': timeSeconds,
        'bonusWordFound': bonusWordFound,
        'tierAwarded': tierAwarded.storageKey,
        'themeName': themeName,
        'secretWord': secretWord,
        'cluesUsed': cluesUsed,
      };

  factory DailyResult.fromJson(Map<String, dynamic> json) => DailyResult(
        dateKey: json['dateKey'] as String,
        completed: json['completed'] as bool? ?? false,
        timeSeconds: json['timeSeconds'] as int? ?? 0,
        bonusWordFound: json['bonusWordFound'] as bool? ?? false,
        tierAwarded: PropertyTierDisplay.fromStorageKey(json['tierAwarded'] as String?),
        themeName: json['themeName'] as String?,
        secretWord: json['secretWord'] as String?,
        cluesUsed: json['cluesUsed'] as int? ?? 0,
      );
}

// Cumulative Daily Estate Challenge progress. `lastPlayedDateKey` is the
// UTC date key (see daily_seed.dart) of the most recent attempt --
// playing today is blocked once it equals today's date key.
class DailyChallengeData {
  final String? lastPlayedDateKey;
  final int streak;
  final int completions;
  final int totalCompletionSeconds;
  final int bonusWordsFound;
  final DailyResult? lastResult;

  // Clues used on the day cluesDateKey (spec-05), kept so leaving and
  // reopening today's puzzle doesn't hand the clues back. Read through
  // cluesUsedOn, which treats any other day as 0.
  final String? cluesDateKey;
  final int cluesUsed;

  const DailyChallengeData({
    required this.lastPlayedDateKey,
    required this.streak,
    required this.completions,
    required this.totalCompletionSeconds,
    required this.bonusWordsFound,
    required this.lastResult,
    this.cluesDateKey,
    this.cluesUsed = 0,
  });

  int cluesUsedOn(String dateKey) => cluesDateKey == dateKey ? cluesUsed.clamp(0, 3) : 0;

  factory DailyChallengeData.initial() => const DailyChallengeData(
        lastPlayedDateKey: null,
        streak: 0,
        completions: 0,
        totalCompletionSeconds: 0,
        bonusWordsFound: 0,
        lastResult: null,
      );

  double get averageCompletionSeconds =>
      completions == 0 ? 0 : totalCompletionSeconds / completions;

  DailyChallengeData copyWith({
    String? lastPlayedDateKey,
    int? streak,
    int? completions,
    int? totalCompletionSeconds,
    int? bonusWordsFound,
    DailyResult? lastResult,
    String? cluesDateKey,
    int? cluesUsed,
  }) {
    return DailyChallengeData(
      lastPlayedDateKey: lastPlayedDateKey ?? this.lastPlayedDateKey,
      streak: streak ?? this.streak,
      completions: completions ?? this.completions,
      totalCompletionSeconds: totalCompletionSeconds ?? this.totalCompletionSeconds,
      bonusWordsFound: bonusWordsFound ?? this.bonusWordsFound,
      lastResult: lastResult ?? this.lastResult,
      cluesDateKey: cluesDateKey ?? this.cluesDateKey,
      cluesUsed: cluesUsed ?? this.cluesUsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'lastPlayedDateKey': lastPlayedDateKey,
        'streak': streak,
        'completions': completions,
        'totalCompletionSeconds': totalCompletionSeconds,
        'bonusWordsFound': bonusWordsFound,
        'lastResult': lastResult?.toJson(),
        'cluesDateKey': cluesDateKey,
        'cluesUsed': cluesUsed,
      };

  factory DailyChallengeData.fromJson(Map<String, dynamic> json) => DailyChallengeData(
        lastPlayedDateKey: json['lastPlayedDateKey'] as String?,
        streak: json['streak'] as int? ?? 0,
        completions: json['completions'] as int? ?? 0,
        totalCompletionSeconds: json['totalCompletionSeconds'] as int? ?? 0,
        bonusWordsFound: json['bonusWordsFound'] as int? ?? 0,
        lastResult: json['lastResult'] != null
            ? DailyResult.fromJson(json['lastResult'] as Map<String, dynamic>)
            : null,
        cluesDateKey: json['cluesDateKey'] as String?,
        cluesUsed: json['cluesUsed'] as int? ?? 0,
      );
}
