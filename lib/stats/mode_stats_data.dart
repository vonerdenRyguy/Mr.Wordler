// Cross-mode personal-best tracking (Infinite Estate's high score, Theme
// Rush's best time per theme). Kept separate from PortfolioData since
// it's stats, not progression/currency -- the Stats screen (a later
// phase) reads from here.
class ModeStatsData {
  final int infiniteEstateHighScore;
  final Map<String, int> themeRushBestSeconds; // themeId -> best time

  const ModeStatsData({
    required this.infiniteEstateHighScore,
    required this.themeRushBestSeconds,
  });

  factory ModeStatsData.initial() => const ModeStatsData(
        infiniteEstateHighScore: 0,
        themeRushBestSeconds: {},
      );

  ModeStatsData copyWith({
    int? infiniteEstateHighScore,
    Map<String, int>? themeRushBestSeconds,
  }) {
    return ModeStatsData(
      infiniteEstateHighScore: infiniteEstateHighScore ?? this.infiniteEstateHighScore,
      themeRushBestSeconds: themeRushBestSeconds ?? this.themeRushBestSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'infiniteEstateHighScore': infiniteEstateHighScore,
        'themeRushBestSeconds': themeRushBestSeconds,
      };

  factory ModeStatsData.fromJson(Map<String, dynamic> json) => ModeStatsData(
        infiniteEstateHighScore: json['infiniteEstateHighScore'] as int? ?? 0,
        themeRushBestSeconds: (json['themeRushBestSeconds'] as Map<String, dynamic>?)
                ?.map((key, value) => MapEntry(key, value as int)) ??
            const {},
      );
}
