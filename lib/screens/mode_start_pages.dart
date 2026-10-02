import 'package:flutter/material.dart';

import '../stats/leaderboard.dart';
import '../ui/mode_start_view.dart';
import '../ui/tokens.dart';
import 'game_screen.dart';
import 'time_attack_screen.dart';

// Start pages for the modes that have one (Theme Rush's lives inside its
// own screen, since the theme is picked there). Start replaces the start
// page with the round, so leaving a round goes straight back to Home.

class FreePlayStartPage extends StatelessWidget {
  const FreePlayStartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: loadLeaderboardEntries(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const [];
        return ModeStartView(
          color: WModeColors.freePlay,
          icon: Icons.grid_on,
          title: 'Free Play',
          description: 'Build words at your own pace.',
          rows: const [
            ModeStartRow('21', 'Letters in your rack'),
            ModeStartRow('∞', 'No clock'),
            ModeStartRow('✓', "Check your words when you're done"),
          ],
          stats: [
            ModeStartStat('Best time', entries.isEmpty ? '-' : '${entries.first['displayTime']}'),
            ModeStartStat('Wins', '${entries.length}'),
          ],
          onStart: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const GameScreen()),
          ),
        );
      },
    );
  }
}

class TimeAttackStartPage extends StatelessWidget {
  const TimeAttackStartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final last = TimeAttackScreen.lastResultThisSession;
    return ModeStartView(
      color: WModeColors.timeAttack,
      icon: Icons.timer_outlined,
      title: 'Time Attack',
      description: 'Use every letter before the clock runs out.',
      rows: const [
        ModeStartRow('21', 'Letters in your rack'),
        ModeStartRow('3', 'Minutes on the clock'),
        ModeStartRow('\$', 'Finish faster, earn more coins'),
      ],
      stats: [if (last != null) ModeStartStat('Last round', last)],
      startLabel: 'Start - 3:00',
      onStart: () => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TimeAttackScreen()),
      ),
    );
  }
}
