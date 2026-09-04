import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily/daily_challenge_controller.dart';
import '../portfolio/level_info.dart';
import '../portfolio/portfolio_controller.dart';
import 'daily_challenge_screen.dart';
import 'infinite_estate_screen.dart';
import 'portfolio_screen.dart';
import 'stats_screen.dart';
import 'theme_rush_screen.dart';
import 'time_attack_screen.dart';

class _ModeInfo {
  final String title;
  final String navLabel;
  final String tagline;
  final String explanation;
  final IconData icon;
  final WidgetBuilder screenBuilder;

  const _ModeInfo({
    required this.title,
    required this.navLabel,
    required this.tagline,
    required this.explanation,
    required this.icon,
    required this.screenBuilder,
  });
}

final List<_ModeInfo> _modes = [
  _ModeInfo(
    title: 'Daily Estate Challenge',
    navLabel: 'Daily',
    tagline: "Today's shared puzzle",
    explanation: 'Every player gets the exact same 21 letters today -- generated from '
        "today's date, so it's identical for everyone. Place every letter into valid, "
        'connected crossword-style words to empty the pool. Each day also hides a '
        'bonus word somewhere in the letters; find it for an upgraded reward. You get '
        'one attempt per day, so plan your board carefully before committing.',
    icon: Icons.today,
    screenBuilder: (context) => const DailyChallengeScreen(),
  ),
  _ModeInfo(
    title: 'Time Attack',
    navLabel: 'Time Attack',
    tagline: 'Beat the clock',
    explanation: 'The same core game as Free Play, but you only get 3 minutes. Empty '
        'your 21-letter rack into valid, connected words before time runs out to win '
        'coins and XP -- the faster you finish, the more you earn. A quick session for '
        'between Daily Challenges.',
    icon: Icons.timer,
    screenBuilder: (context) => const TimeAttackScreen(),
  ),
  _ModeInfo(
    title: 'Theme Rush',
    navLabel: 'Theme Rush',
    tagline: 'Race to one themed word',
    explanation: "You'll be given a theme -- Animals, Food, or Countries -- and a rack "
        'of letters. Build just one valid, connected word matching the theme as fast '
        'as you can; the timer stops the instant it appears on the board. Your best '
        'time for each theme is tracked separately.',
    icon: Icons.category,
    screenBuilder: (context) => const ThemeRushScreen(),
  ),
  _ModeInfo(
    title: 'Infinite Estate',
    navLabel: 'Infinite',
    tagline: 'Endless building',
    explanation: 'A huge, pannable board and a rack that refills itself the instant '
        "you place a tile -- there's no pool to empty and no clock. Build for as long "
        'as you like; your score is based on word length and letter rarity. End the '
        'session anytime to bank coins and XP based on your final score.',
    icon: Icons.all_inclusive,
    screenBuilder: (context) => const InfiniteEstateScreen(),
  ),
];

// Entry point to the four game modes: a swipeable, bottom-nav-driven
// browser. Swipe left/right or tap a bottom nav item to see each mode's
// explanation, then tap Play to launch it.
class ModeSelectScreen extends ConsumerStatefulWidget {
  const ModeSelectScreen({super.key});

  @override
  ConsumerState<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends ConsumerState<ModeSelectScreen> {
  final _pageController = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    final levelInfo = levelInfoForXp(portfolio.totalXp);
    final dailyStreak = ref.watch(dailyChallengeProvider).streak;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Modes'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Stats',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const StatsScreen()),
            ),
          ),
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 4.0),
              child: Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  side: const BorderSide(color: Colors.deepPurple, width: 2.0),
                ),
                child: ListTile(
                  leading: const Icon(Icons.emoji_events, color: Colors.deepPurple),
                  title: Text('Level ${levelInfo.level}'),
                  subtitle: Text(
                      '${portfolio.currency} coins  |  Streak: $dailyStreak day${dailyStreak == 1 ? '' : 's'}'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _modes.length,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) => _ModeDetailPage(mode: _modes[index]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _goToPage,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.deepPurple,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white60,
        items: [
          for (final mode in _modes)
            BottomNavigationBarItem(icon: Icon(mode.icon), label: mode.navLabel),
        ],
      ),
    );
  }
}

class _ModeDetailPage extends StatelessWidget {
  const _ModeDetailPage({required this.mode});

  final _ModeInfo mode;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(mode.icon, size: 56, color: Colors.deepPurple),
          const SizedBox(height: 12),
          Text(mode.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const SizedBox(height: 4),
          Text(mode.tagline, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 16),
          Text(mode.explanation, style: const TextStyle(fontSize: 15, height: 1.4)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: mode.screenBuilder),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text('Play ${mode.title}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
