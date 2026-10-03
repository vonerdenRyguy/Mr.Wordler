import 'package:flutter/material.dart';

import '../ui/mode_start_view.dart';
import '../ui/tokens.dart';
import 'time_attack_screen.dart';

// Time Attack's start page. Start replaces it with the round, so leaving
// a round goes straight back to Home.

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
