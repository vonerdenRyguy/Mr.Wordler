import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily/daily_challenge_controller.dart';
import '../portfolio/level_info.dart';
import '../portfolio/portfolio_controller.dart';
import '../stats/leaderboard.dart';
import '../stats/mode_stats_controller.dart';
import '../theme_rush/theme_category.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../ui/wordler_scaffold.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailyChallengeProvider);
    final modeStats = ref.watch(modeStatsProvider);
    final portfolio = ref.watch(portfolioProvider);
    final levelInfo = levelInfoForXp(portfolio.totalXp);

    return WordlerScaffold(
      title: 'Stats',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          _StatsSection(
            title: 'Overall',
            rows: [
              _StatRow('Level', '${levelInfo.level}'),
              _StatRow('Total XP', '${portfolio.totalXp}'),
              _StatRow('Coins', '${portfolio.currency}'),
            ],
          ),
          const SizedBox(height: WSize.gap3),
          _StatsSection(
            title: 'Daily Estate Challenge',
            rows: [
              _StatRow('Current streak', '${daily.streak} day${daily.streak == 1 ? '' : 's'}'),
              _StatRow('Completions', '${daily.completions}'),
              _StatRow('Average time',
                  daily.completions == 0 ? '--' : _formatSeconds(daily.averageCompletionSeconds.round())),
              _StatRow('Bonus words found', '${daily.bonusWordsFound}'),
            ],
          ),
          const SizedBox(height: WSize.gap3),
          _StatsSection(
            title: 'Theme Rush (best times)',
            rows: [
              for (final theme in kThemeCategories)
                _StatRow(
                  theme.name,
                  modeStats.themeRushBestSeconds.containsKey(theme.id)
                      ? _formatSeconds(modeStats.themeRushBestSeconds[theme.id]!)
                      : 'Not played yet',
                ),
            ],
          ),
          const SizedBox(height: WSize.gap3),
          _StatsSection(
            title: 'Infinite Estate',
            rows: [
              _StatRow('High score', '${modeStats.infiniteEstateHighScore}'),
            ],
          ),
          const SizedBox(height: WSize.gap3),
          // Free Play's leaderboard (it used to be a button on the menu).
          FutureBuilder<List<Map<String, dynamic>>>(
            future: loadLeaderboardEntries(),
            builder: (context, snapshot) {
              final entries = (snapshot.data ?? const []).take(10).toList();
              return _StatsSection(
                title: 'Free Play top times',
                emptyText: snapshot.hasData && entries.isEmpty ? 'No wins yet' : null,
                rows: [
                  for (int i = 0; i < entries.length; i++)
                    _StatRow('${i + 1}. ${entries[i]['name']}', '${entries[i]['displayTime']}'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatSeconds(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _StatRow {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.title, required this.rows, this.emptyText});

  final String title;
  final List<_StatRow> rows;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(title, style: WText.heading.copyWith(fontSize: 22))),
          const SizedBox(height: WSize.gap2),
          if (emptyText != null) Text(emptyText!, style: WText.body.copyWith(color: WColors.muted)),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Expanded(child: Text(row.label, style: WText.body)),
                  const SizedBox(width: WSize.gap2),
                  Text(row.value, style: WText.number.copyWith(fontSize: 20)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
