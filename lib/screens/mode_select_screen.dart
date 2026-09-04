import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily/daily_challenge_controller.dart';
import '../portfolio/level_info.dart';
import '../portfolio/portfolio_controller.dart';
import 'daily_challenge_screen.dart';
import 'portfolio_screen.dart';
import 'time_attack_screen.dart';

// Entry point to the four game modes (Daily Estate Challenge, Time Attack,
// Theme Rush, Infinite Estate). Only Time Attack is built so far; the
// others are wired up as they're built in later phases. Streak will show
// here once the Daily Estate Challenge exists.
class ModeSelectScreen extends ConsumerWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    final levelInfo = levelInfoForXp(portfolio.totalXp);
    final dailyStreak = ref.watch(dailyChallengeProvider).streak;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Modes'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_work),
            tooltip: 'Portfolio',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PortfolioScreen()),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.orangeAccent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Card(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
                side: const BorderSide(color: Colors.deepPurple, width: 2.0),
              ),
              child: ListTile(
                leading: const Icon(Icons.emoji_events, color: Colors.deepPurple),
                title: Text('Level ${levelInfo.level}'),
                subtitle: Text('${portfolio.currency} coins  |  Streak: $dailyStreak day${dailyStreak == 1 ? '' : 's'}'),
                trailing: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PortfolioScreen()),
                  ),
                  child: const Text('Portfolio'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              title: 'Daily Estate Challenge',
              subtitle: "Today's shared puzzle. One attempt a day.",
              icon: Icons.today,
              enabled: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DailyChallengeScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              title: 'Time Attack',
              subtitle: 'Empty the pool before the clock runs out.',
              icon: Icons.timer,
              enabled: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TimeAttackScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              title: 'Theme Rush',
              subtitle: 'Race to place one themed word. Coming soon.',
              icon: Icons.category,
              enabled: false,
              onTap: () => _showComingSoon(context, 'Theme Rush'),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              title: 'Infinite Estate',
              subtitle: 'Endless board, endless letters. Coming soon.',
              icon: Icons.all_inclusive,
              enabled: false,
              onTap: () => _showComingSoon(context, 'Infinite Estate'),
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String modeName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$modeName is coming soon!')),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: enabled ? Colors.white : Colors.white70,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: const BorderSide(color: Colors.deepPurple, width: 2.0),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Colors.deepPurple, size: 32),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
        subtitle: Text(subtitle),
        trailing: enabled ? const Icon(Icons.chevron_right, color: Colors.deepPurple) : null,
      ),
    );
  }
}
