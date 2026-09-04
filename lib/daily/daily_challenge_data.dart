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

  const DailyResult({
    required this.dateKey,
    required this.completed,
    required this.timeSeconds,
    required this.bonusWordFound,
    required this.tierAwarded,
  });

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'completed': completed,
        'timeSeconds': timeSeconds,
        'bonusWordFound': bonusWordFound,
        'tierAwarded': tierAwarded.storageKey,
      };

  factory DailyResult.fromJson(Map<String, dynamic> json) => DailyResult(
        dateKey: json['dateKey'] as String,
        completed: json['completed'] as bool? ?? false,
        timeSeconds: json['timeSeconds'] as int? ?? 0,
        bonusWordFound: json['bonusWordFound'] as bool? ?? false,
        tierAwarded: PropertyTierDisplay.fromStorageKey(json['tierAwarded'] as String?),
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

  const DailyChallengeData({
    required this.lastPlayedDateKey,
    required this.streak,
    required this.completions,
    required this.totalCompletionSeconds,
    required this.bonusWordsFound,
    required this.lastResult,
  });

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
  }) {
    return DailyChallengeData(
      lastPlayedDateKey: lastPlayedDateKey ?? this.lastPlayedDateKey,
      streak: streak ?? this.streak,
      completions: completions ?? this.completions,
      totalCompletionSeconds: totalCompletionSeconds ?? this.totalCompletionSeconds,
      bonusWordsFound: bonusWordsFound ?? this.bonusWordsFound,
      lastResult: lastResult ?? this.lastResult,
    );
  }

  Map<String, dynamic> toJson() => {
        'lastPlayedDateKey': lastPlayedDateKey,
        'streak': streak,
        'completions': completions,
        'totalCompletionSeconds': totalCompletionSeconds,
        'bonusWordsFound': bonusWordsFound,
        'lastResult': lastResult?.toJson(),
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
      );
}
