import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily/daily_challenge_controller.dart';
import '../portfolio/level_info.dart';
import '../portfolio/portfolio_controller.dart';
import '../stats/mode_stats_controller.dart';
import '../theme_rush/theme_category.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailyChallengeProvider);
    final modeStats = ref.watch(modeStatsProvider);
    final portfolio = ref.watch(portfolioProvider);
    final levelInfo = levelInfoForXp(portfolio.totalXp);

    return Scaffold(
      appBar: AppBar(title: const Text('Stats'), backgroundColor: Colors.deepPurple),
      backgroundColor: Colors.orangeAccent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _StatsSection(
              title: 'Overall',
              rows: [
                _StatRow('Level', '${levelInfo.level}'),
                _StatRow('Total XP', '${portfolio.totalXp}'),
                _StatRow('Coins', '${portfolio.currency}'),
              ],
            ),
            const SizedBox(height: 16),
            _StatsSection(
              title: 'Daily Estate Challenge',
              rows: [
                _StatRow('Current streak', '${daily.streak} day${daily.streak == 1 ? '' : 's'}'),
                _StatRow('Completions', '${daily.completions}'),
                _StatRow('Average time', daily.completions == 0
                    ? '--'
                    : _formatSeconds(daily.averageCompletionSeconds.round())),
                _StatRow('Bonus words found', '${daily.bonusWordsFound}'),
              ],
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            _StatsSection(
              title: 'Infinite Estate',
              rows: [
                _StatRow('High score', '${modeStats.infiniteEstateHighScore}'),
              ],
            ),
          ],
        ),
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
  const _StatsSection({required this.title, required this.rows});

  final String title;
  final List<_StatRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: const BorderSide(color: Colors.deepPurple, width: 2.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            const Divider(),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(row.label),
                    Text(row.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
