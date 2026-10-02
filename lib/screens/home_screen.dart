import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily/daily_challenge_controller.dart';
import '../game/letter_tile.dart';
import '../portfolio/level_info.dart';
import '../portfolio/portfolio_controller.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../village/magic_word.dart';
import '../village/village_save.dart';
import 'daily_challenge_screen.dart';
import 'game_screen.dart';
import 'infinite_estate_screen.dart';
import 'portfolio_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'theme_rush_screen.dart';
import 'time_attack_screen.dart';

// The app's one entry screen: your level and coins, your village, today's
// puzzle, and the three quick modes. Replaces the old menu and the
// swipeable Game Modes screen.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // "Journal X/8" on the village card; null = no village saved yet.
  int? _journalCount;

  @override
  void initState() {
    super.initState();
    _loadJournalCount();
  }

  Future<void> _loadJournalCount() async {
    final saved = await VillageSaveController().load();
    if (!mounted) return;
    setState(() => _journalCount = saved?.discoveredWords.length);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    // The village (and so the Journal count) may have changed.
    _loadJournalCount();
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    final level = levelInfoForXp(portfolio.totalXp);
    final daily = ref.watch(dailyChallengeProvider);
    final playedToday = ref.read(dailyChallengeProvider.notifier).hasPlayedToday(DateTime.now());

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        backgroundColor: WColors.paper,
        body: SafeArea(
          // Scrolls on small phones / big text instead of overflowing; on a
          // normal phone the spacer pushes the bottom row down.
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(WSize.screenPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopBar(
                        level: level,
                        coins: portfolio.currency,
                        onLevel: () => _open(const PortfolioScreen()),
                        onSettings: () => _open(const SettingsScreen()),
                      ),
                      const SizedBox(height: 14),
                      const _TileTitle(),
                      const SizedBox(height: 14),
                      _VillageCard(
                        journalCount: _journalCount,
                        onVisit: () => _open(const InfiniteEstateScreen()),
                      ),
                      const SizedBox(height: 14),
                      _DailyCard(
                        played: playedToday,
                        streak: daily.streak,
                        onTap: () => _open(const DailyChallengeScreen()),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _ModeCard(
                              letter: 'F',
                              color: WModeColors.freePlay,
                              name: 'Free Play',
                              line: 'No clock',
                              onTap: () => _open(const GameScreen()),
                            ),
                          ),
                          const SizedBox(width: WSize.gap2),
                          Expanded(
                            child: _ModeCard(
                              letter: 'T',
                              color: WModeColors.timeAttack,
                              name: 'Time Attack',
                              line: '3 minutes',
                              onTap: () => _open(const TimeAttackScreen()),
                            ),
                          ),
                          const SizedBox(width: WSize.gap2),
                          Expanded(
                            child: _ModeCard(
                              letter: 'R',
                              color: WModeColors.themeRush,
                              name: 'Theme Rush',
                              line: 'One theme word',
                              onTap: () => _open(const ThemeRushScreen()),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ChunkyButton(
                              label: 'Portfolio',
                              icon: Icons.home_work,
                              kind: ChunkyKind.secondary,
                              expand: true,
                              onPressed: () => _open(const PortfolioScreen()),
                            ),
                          ),
                          const SizedBox(width: WSize.gap3),
                          Expanded(
                            child: ChunkyButton(
                              label: 'Stats',
                              icon: Icons.bar_chart,
                              kind: ChunkyKind.secondary,
                              expand: true,
                              onPressed: () => _open(const StatsScreen()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.level, required this.coins, required this.onLevel, required this.onSettings});

  final LevelInfo level;
  final int coins;
  final VoidCallback onLevel;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Level ${level.level}, ${level.xpIntoLevel} of ${level.xpForNextLevel} XP. Open Portfolio',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onLevel,
              child: Container(
                height: 52,
                margin: const EdgeInsets.only(bottom: WSize.lipSmall),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: WColors.card,
                  border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: wLip(WSize.lipSmall),
                ),
                child: Row(
                  children: [
                    _Badge(size: 32, color: WColors.sun, child: Text('${level.level}', style: WText.button)),
                    const SizedBox(width: WSize.gap2),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Level ${level.level} · ${level.xpIntoLevel} / ${level.xpForNextLevel} XP',
                            style: WText.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: level.progress,
                              minHeight: 8,
                              color: WColors.grass,
                              backgroundColor: WColors.boardCell,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: WSize.gap2),
        Semantics(
          label: '$coins coins',
          excludeSemantics: true,
          child: Container(
            height: 52,
            margin: const EdgeInsets.only(bottom: WSize.lipSmall),
            padding: const EdgeInsets.only(left: 6, right: 12),
            decoration: BoxDecoration(
              color: WColors.card,
              border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
              borderRadius: BorderRadius.circular(WSize.radiusChip),
              boxShadow: wLip(WSize.lipSmall),
            ),
            child: Row(
              children: [
                const _Badge(size: 28, color: WColors.sun, child: Icon(Icons.monetization_on, size: 18, color: WColors.ink)),
                const SizedBox(width: 6),
                Text('$coins', style: WText.button),
              ],
            ),
          ),
        ),
        const SizedBox(width: WSize.gap2),
        ChunkyIconButton(icon: Icons.settings, tooltip: 'Settings', onPressed: onSettings),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.size, required this.color, required this.child});

  final double size;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
      ),
      child: child,
    );
  }
}

// "MR WORDLER" spelled in letter tiles; M and R in sun.
class _TileTitle extends StatelessWidget {
  const _TileTitle();

  @override
  Widget build(BuildContext context) {
    Widget tile(String letter, {Color? face}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: SizedBox(
            width: 32,
            height: 40,
            child: LetterTile(letter: letter, faceColor: face),
          ),
        );
    return Semantics(
      label: 'Mr. Wordler',
      header: true,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile('M', face: WColors.sun),
            tile('R', face: WColors.sun),
            const SizedBox(width: 8),
            for (final l in 'WORDLER'.split('')) tile(l),
          ],
        ),
      ),
    );
  }
}

class _VillageCard extends StatelessWidget {
  const _VillageCard({required this.journalCount, required this.onVisit});

  final int? journalCount;
  final VoidCallback onVisit;

  @override
  Widget build(BuildContext context) {
    final count = journalCount;
    return ChunkyCard(
      hero: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              SizedBox(
                height: 150,
                width: double.infinity,
                child: Image.asset(
                  'assets/images/village_preview.png',
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stack) => Container(color: WColors.leafTint),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: WColors.card,
                    border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                    borderRadius: BorderRadius.circular(WSize.radiusChip),
                  ),
                  child: Text(
                    count == null ? 'New village' : 'Journal $count/${kMagicWords.length}',
                    style: WText.label.copyWith(color: WColors.ink),
                  ),
                ),
              ),
            ],
          ),
          Container(height: WSize.outline, color: WColors.ink),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Your village', style: WText.heading),
                const SizedBox(height: 2),
                Text('Spell magic words to raise buildings. No clock.', style: WText.body.copyWith(color: WColors.muted)),
                const SizedBox(height: WSize.gap3),
                ChunkyButton(
                  label: 'Visit your village',
                  size: ChunkySize.big,
                  expand: true,
                  onPressed: onVisit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.played, required this.streak, required this.onTap});

  final bool played;
  final int streak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final streakText = '$streak-day streak';
    return ChunkyCard(
      color: WColors.skyTint,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const SizedBox(width: 48, height: 48, child: LetterTile(letter: 'D', faceColor: WColors.sky)),
          const SizedBox(width: WSize.gap3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Today's puzzle", style: WText.heading.copyWith(fontSize: 21)),
                Text(
                  played ? 'Done for today · $streakText' : 'Not played yet · $streakText',
                  style: WText.bodyBold.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: WSize.gap2),
          Text(played ? 'See result' : 'Play', style: WText.button),
          const Icon(Icons.chevron_right, color: WColors.ink),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.letter,
    required this.color,
    required this.name,
    required this.line,
    required this.onTap,
  });

  final String letter;
  final Color color;
  final String name;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 112 - 20 - 2 * WSize.outline),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 44, height: 44, child: LetterTile(letter: letter, faceColor: color)),
            const SizedBox(height: 6),
            Text(name, style: WText.button.copyWith(fontSize: 17, color: WColors.ink)),
            Text(line, style: WText.label),
          ],
        ),
      ),
    );
  }
}
