import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/valid_word_check.dart' show WordValidator;
import '../daily/daily_challenge_controller.dart';
import '../daily/daily_puzzle.dart';
import '../daily/word_of_the_day.dart';
import '../daily/word_of_the_day_controller.dart';
import '../game/letter_tile.dart';
import '../game/word_landing.dart' show wordCheckProvider;
import '../online/family_online_controller.dart';
import '../online/family_online_models.dart';
import '../portfolio/level_info.dart';
import '../players/family_widgets.dart';
import '../players/family_word.dart';
import '../players/player_summary.dart';
import '../players/players.dart';
import '../portfolio/portfolio_controller.dart';
import '../settings/settings_controller.dart';
import '../settings/word_level.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/min_height_box.dart';
import '../ui/tokens.dart';
import '../village/iso_math.dart';
import '../village/iso_village_view.dart';
import '../village/landmark.dart';
import '../village/magic_word.dart';
import '../village/structures.dart';
import '../village/village_art.dart';
import '../village/village_cards.dart';
import '../village/village_save.dart';
import 'daily_challenge_screen.dart';
import 'family_screens.dart';
import 'family_word_online_screens.dart';
import 'helping_screens.dart';
import 'infinite_estate_screen.dart';
import 'mode_start_pages.dart';
import 'portfolio_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'word_level_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadVillage();
      // Family-word coins won while someone else held the phone.
      claimFamilyCoins(ref, context);
    });
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
    final runs =
        await WordValidator().findValidRuns(saved.boardCells, size, size, isValid: ref.read(wordCheckProvider));
    final meta = await VillageArt.loadMeta().catchError((_) => <String, SpriteMeta>{});
    if (!mounted || generation != _loadGeneration) return;
    final structures = computeStructures(runs);
    // An online family sees which buildings you have (spec-09).
    final counts = <String, int>{};
    for (final s in structures) {
      counts[s.def.word] = (counts[s.def.word] ?? 0) + 1;
    }
    ref.read(familyOnlineProvider.notifier).syncBuildings(counts);
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
    if (!mounted) return;
    // The village (buildings, Journal) may have changed.
    _loadVillage();
    claimFamilyCoins(ref, context);
  }

  // A brand-new player picks a word level before their first Daily.
  // Anyone who has played before stays on Wordsmith (the puzzle as it
  // was) until they change it in Settings.
  Future<void> _openDaily(bool playedToday) async {
    final isNewPlayer = ref.read(settingsProvider).chosenWordLevel == null &&
        ref.read(dailyChallengeProvider).lastPlayedDateKey == null &&
        ref.read(portfolioProvider).totalXp == 0;
    if (isNewPlayer && !playedToday) {
      final picked = await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const WordLevelScreen()));
      if (picked != true || !mounted) return;
    }
    await _open(const DailyChallengeScreen());
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    final wordLevel = ref.watch(settingsProvider).wordLevel;
    final level = levelInfoForXp(portfolio.totalXp);
    final daily = ref.watch(dailyChallengeProvider);
    final now = DateTime.now();
    final playedToday = ref.read(dailyChallengeProvider.notifier).hasPlayedToday(now);
    final words = ref.watch(wordsOfTheDayProvider).valueOrNull;
    final wordOfDay = (words == null || words.isEmpty) ? null : wordOfDayFor(now, words);
    ref.watch(wordOfDayProvider);
    final wordClaimed = ref.read(wordOfDayProvider.notifier).claimedToday(now);
    // Two or more players on this phone: the family features show.
    final players = ref.watch(playersProvider);
    ref.watch(familyWordProvider);
    final familyData = ref.read(familyWordProvider.notifier).today(now);
    // In an online family, the card shows the online family's word (spec-09).
    final online = ref.watch(familyOnlineProvider);
    final onlineFamily = online.stage == OnlineStage.member ? online.family : null;
    final familyWord =
        ((!players.isFamily && onlineFamily == null) || words == null || words.isEmpty) ? null : familyWordFor(now, words);

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
                        player: players.isFamily ? players.current : null,
                        onSwitch: () => ref.read(playerPickedProvider.notifier).state = false,
                        onSettings: () => _open(const SettingsScreen()),
                      ),
                      const SizedBox(height: 8),
                      const _TileTitle(),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _VillageCard(village: _village, onVisit: () => _open(const InfiniteEstateScreen())),
                      ),
                      const SizedBox(height: 8),
                      // Gifts, cheers and requests (spec-10).
                      if (onlineFamily != null) const FromFamilyCard(),
                      if (familyWord != null)
                        _FamilyWordCard(
                          word: familyWord.word,
                          data: onlineFamily != null ? familyWordDataOf(online.day ?? const FamilyDay()) : familyData,
                          players: players,
                          online: onlineFamily,
                          playedToday: playedToday,
                          onTap: () => _open(const FamilyWordScreen()),
                        )
                      else
                        _WordOfDayCard(
                          word: wordOfDay,
                          claimed: wordClaimed,
                          onTap: wordOfDay == null
                              ? null
                              : () => showVillageSheet<void>(
                                    context,
                                    Builder(
                                      builder: (sheetContext) => WordOfDayCard(
                                        word: wordOfDay.word,
                                        meaning: wordOfDay.meaning,
                                        claimed: wordClaimed,
                                        coins: kWordOfDayCoins,
                                        onVisit: () {
                                          Navigator.of(sheetContext).pop();
                                          _open(const InfiniteEstateScreen());
                                        },
                                      ),
                                    ),
                                  ),
                        ),
                      const SizedBox(height: 8),
                      _ModeRowCard(
                        letter: 'D',
                        color: WModeColors.daily,
                        tint: WColors.skyTint,
                        title: 'Daily puzzle',
                        status: (playedToday ? 'Done for today' : 'Not played yet') +
                            (daily.streak >= 2 ? ' · ${daily.streak}-day streak' : ''),
                        note: 'Theme: ${dailyPuzzleFor(now).theme.name}',
                        chip: wordLevel.info.name,
                        chipColor: wordLevel.info.color,
                        action: playedToday ? 'See result' : 'Play',
                        onTap: () => _openDaily(playedToday),
                      ),
                      const SizedBox(height: 8),
                      _ModeRowCard(
                        letter: 'T',
                        color: WModeColors.timeAttack,
                        tint: WColors.coralTint,
                        title: 'Time Attack',
                        status: '3 minutes · win coins',
                        action: 'Play',
                        onTap: () => _open(const TimeAttackStartPage()),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (players.isFamily) ...[
                            Expanded(
                              flex: 3,
                              child: ChunkyButton(
                                label: 'Family',
                                size: ChunkySize.small,
                                kind: ChunkyKind.secondary,
                                expand: true,
                                onPressed: () => _open(const FamilyScreen()),
                              ),
                            ),
                            const SizedBox(width: WSize.gap2),
                          ],
                          Expanded(
                            // The longest word of the three gets a little more room.
                            flex: players.isFamily ? 4 : 1,
                            child: ChunkyButton(
                              label: 'Portfolio',
                              size: players.isFamily ? ChunkySize.small : ChunkySize.normal,
                              icon: players.isFamily ? null : Icons.home_work,
                              kind: ChunkyKind.secondary,
                              expand: true,
                              onPressed: () => _open(const PortfolioScreen()),
                            ),
                          ),
                          const SizedBox(width: WSize.gap3),
                          Expanded(
                            flex: players.isFamily ? 3 : 1,
                            child: ChunkyButton(
                              label: 'Stats',
                              size: players.isFamily ? ChunkySize.small : ChunkySize.normal,
                              icon: players.isFamily ? null : Icons.bar_chart,
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
  const _TopBar({
    required this.level,
    required this.coins,
    required this.onLevel,
    required this.onSettings,
    this.player,
    this.onSwitch,
  });

  // With a family on this phone the level pill becomes "who is playing",
  // and tapping it goes back to "Who's playing?".
  final Player? player;
  final VoidCallback? onSwitch;

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
            label: player != null
                ? '${player!.name} is playing. Switch player'
                : 'Level ${level.level}, ${level.xpIntoLevel} of ${level.xpForNextLevel} XP. Open Portfolio',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: player != null ? onSwitch : onLevel,
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
                child: player != null
                    ? Row(
                        children: [
                          PlayerAvatar(player: player!, size: 34),
                          const SizedBox(width: WSize.gap2),
                          Expanded(
                            child: Text(player!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WText.button.copyWith(fontSize: 18, color: WColors.ink)),
                          ),
                          const Text('Switch', style: WText.label),
                          const SizedBox(width: 4),
                        ],
                      )
                    : Row(
                        children: [
                          _Badge(size: 32, color: WColors.sun, child: Text('${level.level}', style: WText.button)),
                          const SizedBox(width: WSize.gap2),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Level ${level.level}',
                                    style: WText.button.copyWith(fontSize: 17, color: WColors.ink)),
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
                const _Badge(
                    size: 28, color: WColors.sun, child: Icon(Icons.monetization_on, size: 18, color: WColors.ink)),
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
          // At least 96 tall; it takes whatever height the rest of Home
          // leaves, so Home always fills exactly one screen when it can.
          Expanded(
            child: MinHeightBox(
              height: 96,
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
          ),
          Container(height: WSize.outline, color: WColors.ink),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Your village', style: WText.heading),
                // One line on any phone: it shrinks a little rather than wrapping.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('Spell magic words to raise buildings.',
                      maxLines: 1, style: WText.body.copyWith(color: WColors.muted)),
                ),
                const SizedBox(height: WSize.gap2),
                ChunkyButton(
                    label: 'Visit your village', size: ChunkySize.big, expand: true, onPressed: widget.onVisit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Word of the day: the word, one line of its meaning, and whether
/// today's village reward is still to be earned. Tapping opens the sheet.
/// [word] is null while the list loads; the card then just shows its label.
class _WordOfDayCard extends StatelessWidget {
  const _WordOfDayCard({required this.word, required this.claimed, required this.onTap});

  final WordOfDay? word;
  final bool claimed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final word = this.word;
    return Semantics(
      button: word != null,
      label: word == null ? 'Word of the day' : 'Word of the day: ${word.word}. ${word.meaning} Open.',
      excludeSemantics: true,
      child: ChunkyCard(
        color: WColors.sunTint,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('WORD OF THE DAY', maxLines: 1, style: WText.label)),
                if (word != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: claimed ? WColors.leafTint : WColors.sun,
                      border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                      borderRadius: BorderRadius.circular(WSize.radiusChip),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (claimed) ...[
                          const Icon(Icons.check, size: 16, color: WColors.ink),
                          const SizedBox(width: 2),
                        ],
                        Text(claimed ? 'Done' : '+$kWordOfDayCoins coins',
                            style: WText.label.copyWith(color: WColors.ink)),
                      ],
                    ),
                  ),
              ],
            ),
            Text(word?.word ?? '', maxLines: 1, style: WText.heading.copyWith(fontSize: 22)),
            Text(
              word?.meaning ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WText.body.copyWith(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's family word, in the Word of the day's place once two or more
/// players share the phone.
class _FamilyWordCard extends StatelessWidget {
  const _FamilyWordCard({
    required this.word,
    required this.data,
    required this.players,
    required this.playedToday,
    required this.onTap,
    this.online,
  });

  final String word;
  final FamilyWordData data;
  final PlayersState players;
  final bool playedToday;
  final VoidCallback onTap;

  /// The online family, when the word is theirs (spec-09).
  final OnlineFamily? online;

  @override
  Widget build(BuildContext context) {
    final family = online;
    final line = data.solved
        ? 'Found together!'
        : playedToday
            ? (family != null ? 'Waiting for the family to play.' : 'Pass the phone on to find more letters.')
            : 'Finish your Daily to find your letters.';
    return ChunkyCard(
      color: WColors.sunTint,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('FAMILY WORD', maxLines: 1, style: WText.label)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: data.solved ? WColors.leafTint : WColors.sun,
                  border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                  borderRadius: BorderRadius.circular(WSize.radiusChip),
                ),
                child: Text(data.solved ? 'Found' : '+$kFamilyWordEarlyCoins coins each',
                    style: WText.label.copyWith(color: WColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FamilyWordSlots(
            word: word,
            data: data,
            players: players,
            tileSize: 30,
            colorOf: family == null
                ? null
                : (uid) {
                    final m = family.member(uid);
                    return m == null ? null : memberColor(m);
                  },
          ),
          const SizedBox(height: 2),
          Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: WText.body.copyWith(fontSize: 15)),
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
    this.note,
    this.chip,
    this.chipColor,
    required this.action,
    required this.onTap,
  });

  // A small pill after the title (the Daily's word level).
  final String? chip;
  final Color? chipColor;

  final String letter;
  final Color color;
  final Color tint;
  final String title;
  final String status;
  // A second, quieter line (the Daily's theme).
  final String? note;
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
                if (note != null || chip != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    // On a narrow card with big text this line shrinks a
                    // little to stay whole, rather than being cut off.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (chip != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                              decoration: BoxDecoration(
                                color: chipColor ?? WColors.sun,
                                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                                borderRadius: BorderRadius.circular(WSize.radiusChip),
                              ),
                              child: Text(chip!, maxLines: 1, style: WText.label.copyWith(color: WColors.ink)),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (note != null) Text(note!, maxLines: 1, style: WText.label),
                        ],
                      ),
                    ),
                  ),
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
