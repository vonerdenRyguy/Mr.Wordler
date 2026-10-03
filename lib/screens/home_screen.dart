import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/valid_word_check.dart' show WordValidator;
import '../daily/daily_challenge_controller.dart';
import '../game/letter_tile.dart';
import '../game/word_landing.dart' show wordCheckProvider;
import '../portfolio/level_info.dart';
import '../portfolio/portfolio_controller.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../village/iso_math.dart';
import '../village/iso_village_view.dart';
import '../village/landmark.dart';
import '../village/magic_word.dart';
import '../village/structures.dart';
import '../village/village_art.dart';
import '../village/village_save.dart';
import 'daily_challenge_screen.dart';
import 'infinite_estate_screen.dart';
import 'mode_start_pages.dart';
import 'portfolio_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

// The app's one entry screen: your level and coins, a picture of your own
// village, today's puzzle and Time Attack. Fits one screen at normal text
// size.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Null until loaded; hasSave false = "New village".
  ({bool hasSave, int journal, int buildings, VillageScene? scene, ({int r, int c}) focus})? _village;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    // After the first frame, so Home draws straight away with the static
    // picture.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVillage());
  }

  Future<void> _loadVillage() async {
    final generation = ++_loadGeneration;
    final saved = await VillageSaveController().load();
    if (!mounted || generation != _loadGeneration) return;
    if (saved == null || saved.boardCells.every((c) => c == null)) {
      setState(() => _village = (
            hasSave: saved != null,
            journal: saved?.discoveredWords.length ?? 0,
            buildings: 0,
            scene: null,
            focus: (r: 0, c: 0),
          ));
      return;
    }
    const size = InfiniteEstateScreen.boardSize;
    final runs = await WordValidator().findValidRuns(saved.boardCells, size, size, isValid: ref.read(wordCheckProvider));
    final meta = await VillageArt.loadMeta().catchError((_) => <String, SpriteMeta>{});
    if (!mounted || generation != _loadGeneration) return;
    final structures = computeStructures(runs);
    final scene = VillageScene(
      grid: const IsoGrid(boardWidth: size, boardHeight: size),
      boardCells: saved.boardCells,
      structures: structures,
      landmarkIndices: landmarkBoardIndices(size, size).toSet(),
      spriteMeta: meta,
    );
    setState(() => _village = (
          hasSave: true,
          journal: saved.discoveredWords.length,
          buildings: structures.length,
          scene: scene,
          focus: _focusOf(scene, saved.discoveredWords),
        ));
  }

  // Your newest building (the most recently discovered word that's built),
  // else the middle of all your letters.
  ({int r, int c}) _focusOf(VillageScene scene, Set<String> discovered) {
    for (final word in discovered.toList().reversed) {
      for (final s in scene.structures.reversed) {
        if (s.def.word == word) return (r: scene.rowOf(s.middle), c: scene.colOf(s.middle));
      }
    }
    if (scene.structures.isNotEmpty) {
      final s = scene.structures.last;
      return (r: scene.rowOf(s.middle), c: scene.colOf(s.middle));
    }
    return scene.lettersCenter();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    // The village (buildings, Journal) may have changed.
    _loadVillage();
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
          // Fits one screen at normal text size; at large text it scrolls.
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
                      const SizedBox(height: 12),
                      const _TileTitle(),
                      const SizedBox(height: 12),
                      _VillageCard(village: _village, onVisit: () => _open(const InfiniteEstateScreen())),
                      const SizedBox(height: 12),
                      _ModeRowCard(
                        letter: 'D',
                        color: WModeColors.daily,
                        tint: WColors.skyTint,
                        title: 'Daily puzzle',
                        status: (playedToday ? 'Done for today' : 'Not played yet') +
                            (daily.streak >= 2 ? ' · ${daily.streak}-day streak' : ''),
                        action: playedToday ? 'See result' : 'Play',
                        onTap: () => _open(const DailyChallengeScreen()),
                      ),
                      const SizedBox(height: 12),
                      _ModeRowCard(
                        letter: 'T',
                        color: WModeColors.timeAttack,
                        tint: WColors.coralTint,
                        title: 'Time Attack',
                        status: '3 minutes · win coins',
                        action: 'Play',
                        onTap: () => _open(const TimeAttackStartPage()),
                      ),
                      const Spacer(),
                      const SizedBox(height: 12),
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
                          Text('Level ${level.level}', style: WText.button.copyWith(fontSize: 17, color: WColors.ink)),
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
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(
            width: 30,
            height: 36,
            child: LetterTile(letter: letter, faceColor: face, fontSize: 22),
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

class _VillageCard extends StatefulWidget {
  const _VillageCard({required this.village, required this.onVisit});

  final ({bool hasSave, int journal, int buildings, VillageScene? scene, ({int r, int c}) focus})? village;
  final VoidCallback onVisit;

  @override
  State<_VillageCard> createState() => _VillageCardState();
}

class _VillageCardState extends State<_VillageCard> {
  final _camera = TransformationController();

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  ({int r, int c})? _aimedAt;
  Size? _aimedSize;

  // Points the still picture at [focus]. Done after the frame: changing the
  // camera during build would rebuild the map mid-build.
  void _aim(({int r, int c}) focus, Size size, IsoGrid grid) {
    if (focus == _aimedAt && size == _aimedSize) return;
    _aimedAt = focus;
    _aimedSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _camera.value = isoTransformCenteredOn(focus.r, focus.c, size, 0.8, grid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final village = widget.village;
    final scene = village?.scene;
    final chip = village == null || !village.hasSave
        ? 'New village'
        : '${village.buildings} building${village.buildings == 1 ? '' : 's'} · Journal ${village.journal}/${kMagicWords.length}';
    return ChunkyCard(
      hero: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (scene == null)
                  Image.asset(
                    'assets/images/village_preview.png',
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    errorBuilder: (context, error, stack) => Container(color: WColors.leafTint),
                  )
                else
                  // Your own village, as a still picture centered on your
                  // newest building.
                  IgnorePointer(
                    child: LayoutBuilder(builder: (context, constraints) {
                      _aim(village!.focus, constraints.biggest, scene.grid);
                      return ColoredBox(
                        color: WColors.grassField,
                        child: IsoVillageView(scene: scene, transformController: _camera, interactive: false),
                      );
                    }),
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
                    child: Text(chip, style: WText.label.copyWith(color: WColors.ink)),
                  ),
                ),
              ],
            ),
          ),
          Container(height: WSize.outline, color: WColors.ink),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Your village', style: WText.heading),
                Text('Spell magic words to raise buildings.', style: WText.body.copyWith(color: WColors.muted)),
                const SizedBox(height: WSize.gap2),
                ChunkyButton(label: 'Visit your village', size: ChunkySize.big, expand: true, onPressed: widget.onVisit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width mode card: a letter tile, a title and status line, and
/// the action on the right. The whole card is tappable.
class _ModeRowCard extends StatelessWidget {
  const _ModeRowCard({
    required this.letter,
    required this.color,
    required this.tint,
    required this.title,
    required this.status,
    required this.action,
    required this.onTap,
  });

  final String letter;
  final Color color;
  final Color tint;
  final String title;
  final String status;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      color: tint,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 44, height: 44, child: LetterTile(letter: letter, faceColor: color)),
          const SizedBox(width: WSize.gap3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: WText.heading.copyWith(fontSize: 21)),
                Text(status, style: WText.bodyBold.copyWith(fontSize: 15)),
              ],
            ),
          ),
          const SizedBox(width: WSize.gap2),
          Text(action, style: WText.button),
          const Icon(Icons.chevron_right, color: WColors.ink),
        ],
      ),
    );
  }
}
