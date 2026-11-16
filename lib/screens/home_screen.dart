import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/valid_word_check.dart' show WordValidator;
import '../daily/daily_challenge_controller.dart';
import '../daily/daily_puzzle.dart';
import '../daily/word_of_the_day.dart';
import '../daily/word_of_the_day_controller.dart';
import '../dictionary/definition_service.dart';
import '../game/word_landing.dart' show wordCheckProvider;
import '../online/family_online_controller.dart';
import '../online/family_online_models.dart';
import '../online/helping.dart' show HelpItem;
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
import '../ui/home_nav.dart';
import '../ui/min_height_box.dart';
import '../ui/tokens.dart';
import '../village/discovery_journal_view.dart';
import '../village/iso_math.dart';
import '../village/iso_village_view.dart';
import '../village/landmark.dart';
import '../village/magic_word.dart';
import '../village/structures.dart';
import '../village/village_art.dart';
import '../village/village_cards.dart';
import '../village/village_save.dart';
import 'daily_challenge_screen.dart';
import 'family_online_screens.dart';
import 'family_screens.dart';
import 'family_word_online_screens.dart';
import 'helping_screens.dart';
import 'home_tips.dart';
import 'infinite_estate_screen.dart';
import 'mode_start_pages.dart';
import 'portfolio_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'word_level_screen.dart';

typedef _Village = ({
  bool hasSave,
  int journal,
  int buildings,
  VillageScene? scene,
  ({int r, int c}) focus,
  List<String?> rack,
  Set<String> discovered,
});

// The app's one entry screen (spec-11): three pages you swipe between,
// Me | Play | Family, opening on Play. A slim tab bar and page dots show
// where you are; Mr. W sometimes leaves a tip. Each page fills one screen
// at normal text size and only scrolls when the text is very large.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _Village? _village;
  int _loadGeneration = 0;

  final _pages = PageController(initialPage: HomePage.play.index);
  int _page = HomePage.play.index;

  /// How many family items were on screen when the Family page was last
  /// open; the tab's red number counts the ones since.
  int _familySeen = 0;

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

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
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
            rack: saved?.rackCells ?? const [],
            discovered: saved?.discoveredWords ?? const {},
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
          rack: saved.rackCells,
          discovered: saved.discoveredWords,
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

  void _goTo(int page) {
    final reduceMotion = ref.read(settingsProvider).reduceMotion;
    if (reduceMotion) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  void _openJournal() {
    final village = _village;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DiscoveryJournalView(
        rackCells: village?.rack ?? const [],
        discoveredWords: village?.discovered ?? const {},
        loadDefinition: ref.read(definitionServiceProvider).getDefinition,
      ),
    );
  }

  void _openWordOfDay(WordOfDay word, bool claimed) {
    showVillageSheet<void>(
      context,
      Builder(
        builder: (sheetContext) => WordOfDayCard(
          word: word.word,
          meaning: word.meaning,
          claimed: claimed,
          coins: kWordOfDayCoins,
          onVisit: () {
            Navigator.of(sheetContext).pop();
            _open(const InfiniteEstateScreen());
          },
        ),
      ),
    );
  }

  // Pick who to cheer, then the stickers.
  void _pickCheer(OnlineFamily family, String? myUid) {
    final others = [for (final m in family.members) if (m.uid != myUid) m];
    if (others.length == 1) {
      _open(CheerScreen(uid: others.single.uid));
      return;
    }
    showVillageSheet<void>(
      context,
      Builder(
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cheer for who?', style: WText.heading.copyWith(fontSize: 24)),
            const SizedBox(height: WSize.gap3),
            for (final m in others)
              Padding(
                padding: const EdgeInsets.only(bottom: WSize.gap2),
                child: ChunkyCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _open(CheerScreen(uid: m.uid));
                  },
                  child: Row(children: [
                    PlayerAvatar(player: Player(id: m.uid, name: m.name, colorIndex: m.colorIndex), size: 40),
                    const SizedBox(width: WSize.gap3),
                    Expanded(child: Text(m.name, style: WText.button.copyWith(color: WColors.ink))),
                    const Icon(Icons.chevron_right, color: WColors.ink),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    final settings = ref.watch(settingsProvider);
    final wordLevel = settings.wordLevel;
    final level = levelInfoForXp(portfolio.totalXp);
    final daily = ref.watch(dailyChallengeProvider);
    final now = DateTime.now();
    final playedToday = ref.read(dailyChallengeProvider.notifier).hasPlayedToday(now);
    final words = ref.watch(wordsOfTheDayProvider).valueOrNull;
    final wordOfDay = (words == null || words.isEmpty) ? null : wordOfDayFor(now, words);
    ref.watch(wordOfDayProvider);
    final wordClaimed = ref.read(wordOfDayProvider.notifier).claimedToday(now);
    final players = ref.watch(playersProvider);
    ref.watch(familyWordProvider);
    final familyData = ref.read(familyWordProvider.notifier).today(now);
    // In an online family, the family word is the online family's (spec-09).
    final online = ref.watch(familyOnlineProvider);
    final onlineFamily = online.stage == OnlineStage.member ? online.family : null;
    final hasFamily = players.isFamily || onlineFamily != null;
    final familyWord = (!hasFamily || words == null || words.isEmpty) ? null : familyWordFor(now, words);
    final familyWordData = onlineFamily != null ? familyWordDataOf(online.day ?? const FamilyDay()) : familyData;

    // Gifts, cheers and requests (spec-10); the tab counts the new ones.
    final helpItems = onlineFamily == null ? const <HelpItem>[] : myHelpItems(online);
    if (_page == HomePage.family.index) _familySeen = helpItems.length;
    if (helpItems.length < _familySeen) _familySeen = helpItems.length;
    final unseen = helpItems.length - _familySeen;
    HelpItem? request;
    for (final i in helpItems) {
      if (i.asker != null) {
        request = i;
        break;
      }
    }

    final facts = TipFacts(
      playedToday: playedToday,
      buildings: _village?.buildings,
      waitingFromFamily: unseen,
      hasFamily: hasFamily,
      familyWordSolved: familyWordData.solved,
      wordOfDayClaimed: wordClaimed || wordOfDay == null,
      askerName: request?.asker?.name,
      askedLetter: request?.letter,
    );
    final hidden = ref.watch(hiddenTipsProvider);
    final tip = settings.showTips ? homeTipFor(HomePage.values[_page], facts) : null;
    final shownTip = tip == null || hidden.contains(tip.id) ? null : tip;

    final pages = <Widget>[
      _MePage(
        level: level,
        player: players.current,
        wordOfDay: wordOfDay,
        wordClaimed: wordClaimed,
        wordLevel: wordLevel,
        onLevel: () => _open(const PortfolioScreen()),
        onWordOfDay: wordOfDay == null ? null : () => _openWordOfDay(wordOfDay, wordClaimed),
        onJournal: _openJournal,
        onProperties: () => _open(const PortfolioScreen()),
        onStats: () => _open(const StatsScreen()),
        onWordLevel: () => _open(const WordLevelScreen()),
      ),
      _PlayPage(
        village: _village,
        playedToday: playedToday,
        streak: daily.streak,
        theme: dailyPuzzleFor(now).theme.name,
        wordLevel: wordLevel,
        now: now,
        onVisit: () => _open(const InfiniteEstateScreen()),
        onDaily: () => _openDaily(playedToday),
        onTimeAttack: () => _open(const TimeAttackStartPage()),
      ),
      if (!hasFamily)
        _NoFamilyPage(
          onThisPhone: () => _open(const FamilyScreen()),
          onDifferentPhones: () => _open(const FamilyOnlineScreen()),
        )
      else
        _FamilyPage(
          players: players,
          online: onlineFamily,
          myUid: online.account?.uid,
          streak: familyWordData.solved ? familyWordData.streak : 0,
          familyWord: familyWord?.word,
          familyWordData: familyWordData,
          playedToday: playedToday,
          helpItems: helpItems,
          onFamilyWord: () => _open(const FamilyWordScreen()),
          onFromFamily: () => _open(const FromFamilyScreen()),
          onMap: () => _open(const FamilyMapScreen()),
          onCheer: onlineFamily == null ? null : () => _pickCheer(onlineFamily, online.account?.uid),
          onTheFamily: () => _open(const FamilyScreen()),
          onPassPhone: () => ref.read(playerPickedProvider.notifier).state = false,
        ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        backgroundColor: WColors.paper,
        body: Stack(
          children: [
            Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 12, WSize.screenPadding, 4),
                    child: _TopBar(
                      level: level,
                      coins: portfolio.currency,
                      onLevel: () => _goTo(HomePage.me.index),
                      player: players.isFamily ? players.current : null,
                      onSwitch: () => ref.read(playerPickedProvider.notifier).state = false,
                      onSettings: () => _open(const SettingsScreen()),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _page = i),
                    children: pages,
                  ),
                ),
                if (shownTip != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 0, WSize.screenPadding, 6),
                    child: TipBar(
                      key: ValueKey(shownTip.id),
                      text: shownTip.text,
                      onHide: () => ref.read(hiddenTipsProvider.notifier).hide(shownTip.id),
                    ),
                  ),
                PageDots(count: 3, index: _page),
                const SizedBox(height: 6),
                HomeTabBar(
                  index: _page,
                  onTap: _goTo,
                  tabs: [
                    const HomeTabInfo('Me', Icons.person),
                    const HomeTabInfo('Play', Icons.home),
                    HomeTabInfo('Family', Icons.groups, badge: _page == HomePage.family.index ? 0 : unseen),
                  ],
                ),
              ],
            ),
            if (settings.loaded && !settings.homeIntroSeen)
              Positioned.fill(
                child: HomeIntroCard(onDone: () => ref.read(settingsProvider.notifier).markHomeIntroSeen()),
              ),
          ],
        ),
      ),
    );
  }
}

/// A page's boxes fill the screen; with very large text the page scrolls
/// instead of squashing them.
class _PageBody extends StatelessWidget {
  const _PageBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 8, WSize.screenPadding, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

/// A box that takes its share of the page, but never less than [min]
/// (taller with bigger text, so the page scrolls instead of squeezing it).
Widget _grow(int flex, double min, Widget child) => Expanded(
      flex: flex,
      child: Builder(
        builder: (context) => MinHeightBox(height: MediaQuery.textScalerOf(context).scale(min), child: child),
      ),
    );

// ---- Play ---------------------------------------------------------------------

class _PlayPage extends StatelessWidget {
  const _PlayPage({
    required this.village,
    required this.playedToday,
    required this.streak,
    required this.theme,
    required this.wordLevel,
    required this.now,
    required this.onVisit,
    required this.onDaily,
    required this.onTimeAttack,
  });

  final _Village? village;
  final bool playedToday;
  final int streak;
  final String theme;
  final WordLevel wordLevel;
  final DateTime now;
  final VoidCallback onVisit;
  final VoidCallback onDaily;
  final VoidCallback onTimeAttack;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    return _PageBody(children: [
      _grow(5, 230, _VillageCard(village: village, onVisit: onVisit)),
      const SizedBox(height: 10),
      _grow(
        2,
        92,
        _BigModeCard(
          semantics: 'Daily puzzle. ${playedToday ? 'Done for today' : 'Not played yet'}. Theme: $theme',
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [WColors.skyTint, Color(0xFF9ED6F3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          onTap: onDaily,
          badge: _CalendarTile(month: _months[now.month - 1], day: now.day),
          title: 'Daily puzzle',
          lines: [
            Text(
              (playedToday ? 'Done for today' : 'Not played yet') + (streak >= 2 ? ' · $streak-day streak' : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WText.bodyBold.copyWith(fontSize: 15),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _Chip(text: wordLevel.info.name, color: wordLevel.info.color),
                const SizedBox(width: 6),
                Text('Theme: $theme', maxLines: 1, style: WText.label.copyWith(color: const Color(0xFF2A5C78))),
              ]),
            ),
          ],
          action: playedToday ? 'See result' : 'Play',
        ),
      ),
      const SizedBox(height: 10),
      _grow(
        2,
        92,
        _BigModeCard(
          semantics: 'Time Attack. 3 minutes. Beat the clock!',
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [WColors.coralTint, WColors.coralTint, Color(0xFFF8CDBF), Color(0xFFF8CDBF)],
              stops: [0, 0.62, 0.62, 1],
              begin: Alignment(-1, -1),
              end: Alignment(-0.82, -0.55),
              tileMode: TileMode.repeated,
            ),
          ),
          onTap: onTimeAttack,
          badge: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: WColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: WColors.ink, width: WSize.outline),
              boxShadow: wLip(WSize.lipSmall),
            ),
            child: const Icon(Icons.bolt, size: 40, color: Color(0xFFE0662F)),
          ),
          title: 'Time Attack',
          lines: [
            Text('3 minutes. Beat the clock!',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WText.bodyBold.copyWith(fontSize: 15, color: const Color(0xFF8C3218))),
          ],
          action: 'Play',
        ),
      ),
    ]);
  }
}

class _CalendarTile extends StatelessWidget {
  const _CalendarTile({required this.month, required this.day});

  final String month;
  final int day;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 68,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: WColors.white,
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: BorderRadius.circular(12),
        boxShadow: wLip(WSize.lipSmall),
      ),
      child: Column(children: [
        Container(
          width: double.infinity,
          color: WColors.brick,
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(month,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: WText.buttonSmall.copyWith(fontSize: 13, color: WColors.white)),
        ),
        Expanded(
          child: Center(
            child: Text('$day',
                textScaler: TextScaler.noScaling, style: WText.number.copyWith(fontSize: 30, color: WColors.ink)),
          ),
        ),
      ]),
    );
  }
}

/// A big, tappable game card: a picture, the name, a line or two, and a
/// green button.
class _BigModeCard extends StatelessWidget {
  const _BigModeCard({
    required this.semantics,
    required this.decoration,
    required this.onTap,
    required this.badge,
    required this.title,
    required this.lines,
    required this.action,
  });

  final String semantics;
  final BoxDecoration decoration;
  final VoidCallback onTap;
  final Widget badge;
  final String title;
  final List<Widget> lines;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$semantics. $action',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: WSize.lip),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: decoration.copyWith(
            border: Border.all(color: WColors.ink, width: WSize.outline),
            borderRadius: BorderRadius.circular(WSize.radiusCard),
            boxShadow: wLip(WSize.lip),
          ),
          child: Row(children: [
            badge,
            const SizedBox(width: WSize.gap3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: WText.heading.copyWith(fontSize: 24)),
                  ...lines,
                ],
              ),
            ),
            const SizedBox(width: WSize.gap2),
            IgnorePointer(child: ChunkyButton(label: action, size: ChunkySize.small, onPressed: onTap)),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.color = WColors.sun});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
        borderRadius: BorderRadius.circular(WSize.radiusChip),
      ),
      child: Text(text, maxLines: 1, style: WText.label.copyWith(color: WColors.ink)),
    );
  }
}

// ---- Me -----------------------------------------------------------------------

class _MePage extends StatelessWidget {
  const _MePage({
    required this.level,
    required this.player,
    required this.wordOfDay,
    required this.wordClaimed,
    required this.wordLevel,
    required this.onLevel,
    required this.onWordOfDay,
    required this.onJournal,
    required this.onProperties,
    required this.onStats,
    required this.onWordLevel,
  });

  final LevelInfo level;
  final Player player;
  final WordOfDay? wordOfDay;
  final bool wordClaimed;
  final WordLevel wordLevel;
  final VoidCallback onLevel;
  final VoidCallback? onWordOfDay;
  final VoidCallback onJournal;
  final VoidCallback onProperties;
  final VoidCallback onStats;
  final VoidCallback onWordLevel;

  @override
  Widget build(BuildContext context) {
    final toNext = (level.xpForNextLevel - level.xpIntoLevel).clamp(0, 1 << 30);
    final word = wordOfDay;
    return _PageBody(children: [
      Semantics(
        button: true,
        label: 'Level ${level.level}. $toNext points to Level ${level.level + 1}. Open My properties',
        excludeSemantics: true,
        child: ChunkyCard(
          color: WColors.sunTint,
          onTap: onLevel,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: level.progress,
                    strokeWidth: 7,
                    color: WColors.grass,
                    backgroundColor: WColors.boardCell,
                  ),
                ),
                PlayerAvatar(player: player, size: 54),
              ]),
            ),
            const SizedBox(width: WSize.gap3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Level ${level.level}', style: WText.heading.copyWith(fontSize: 28)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: level.progress,
                    minHeight: 12,
                    color: WColors.grass,
                    backgroundColor: WColors.boardCell,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$toNext points to Level ${level.level + 1}', style: WText.label),
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      _grow(
        3,
        180,
        Semantics(
          button: word != null,
          label: word == null ? 'Word of the day' : 'Word of the day: ${word.word}. ${word.meaning} Open.',
          excludeSemantics: true,
          child: ChunkyCard(
            color: WColors.leafTint,
            onTap: onWordOfDay,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Expanded(child: Text('WORD OF THE DAY', maxLines: 1, style: WText.label)),
                  if (word != null) _Chip(text: wordClaimed ? 'Done' : '+$kWordOfDayCoins coins', color: wordClaimed ? WColors.card : WColors.sun),
                ]),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(word?.word ?? '', maxLines: 1, style: WText.title.copyWith(fontSize: 42, letterSpacing: 1.5)),
                ),
                Text(word?.meaning ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: WText.body),
                if (word != null && !wordClaimed)
                  Text('Spell it in your village', style: WText.label.copyWith(color: const Color(0xFF2F5A1E))),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      _grow(
        4,
        200,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _Square(icon: Icons.menu_book, color: WColors.sky, label: 'Word journal', onTap: onJournal)),
              const SizedBox(width: 10),
              Expanded(child: _Square(icon: Icons.home_work, color: WColors.leaf, label: 'My properties', onTap: onProperties)),
            ]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _Square(icon: Icons.bar_chart, color: WColors.coral, label: 'My stats', onTap: onStats)),
              const SizedBox(width: 10),
              Expanded(
                child: _Square(
                  icon: Icons.school,
                  color: wordLevel.info.color,
                  label: 'Word level',
                  sub: wordLevel.info.name,
                  onTap: onWordLevel,
                ),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

/// A big square button: a round picture and a word or two under it.
class _Square extends StatelessWidget {
  const _Square({required this.icon, required this.color, required this.label, required this.onTap, this.sub});

  final IconData icon;
  final Color color;
  final String label;
  final String? sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: sub == null ? label : '$label: $sub',
      excludeSemantics: true,
      child: ChunkyCard(
        onTap: onTap,
        padding: const EdgeInsets.all(8),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: WColors.ink, width: WSize.outline),
                ),
                child: Icon(icon, size: 28, color: WColors.ink),
              ),
              const SizedBox(height: 6),
              Text(label, style: WText.button.copyWith(color: WColors.ink)),
              if (sub != null) Text(sub!, style: WText.label),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---- Family -------------------------------------------------------------------

class _FamilyPage extends StatelessWidget {
  const _FamilyPage({
    required this.players,
    required this.online,
    required this.myUid,
    required this.streak,
    required this.familyWord,
    required this.familyWordData,
    required this.playedToday,
    required this.helpItems,
    required this.onFamilyWord,
    required this.onFromFamily,
    required this.onMap,
    required this.onCheer,
    required this.onTheFamily,
    required this.onPassPhone,
  });

  final PlayersState players;
  final OnlineFamily? online;
  final String? myUid;
  final int streak;
  final String? familyWord;
  final FamilyWordData familyWordData;
  final bool playedToday;
  final List<HelpItem> helpItems;
  final VoidCallback onFamilyWord;
  final VoidCallback onFromFamily;
  final VoidCallback onMap;
  final VoidCallback? onCheer;
  final VoidCallback onTheFamily;
  final VoidCallback onPassPhone;

  @override
  Widget build(BuildContext context) {
    final family = online;
    final faces = family != null
        ? [for (final m in family.members) Player(id: m.uid, name: m.name, colorIndex: m.colorIndex)]
        : players.players;
    final name = family?.name ?? 'Your family';
    final word = familyWord;
    final line = familyWordData.solved
        ? 'Found together!'
        : playedToday
            ? (family != null ? 'Waiting for the family to play.' : 'Pass the phone on to find more letters.')
            : 'Play the Daily to find your letters.';
    return _PageBody(children: [
      // The banner: the family's name, everyone's faces, the streak.
      Container(
        margin: const EdgeInsets.only(bottom: WSize.lipHero),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE59A), WColors.sun],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(color: WColors.ink, width: WSize.outline),
          borderRadius: BorderRadius.circular(WSize.radiusHero),
          boxShadow: wLip(WSize.lipHero),
        ),
        child: Column(children: [
          Semantics(
            header: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(name, maxLines: 1, style: WText.title.copyWith(fontSize: 32)),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [for (final p in faces) PlayerAvatar(player: p, size: 40)],
          ),
          if (streak >= 2) ...[
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.local_fire_department, color: WColors.brick, size: 22),
              Text('$streak days in a row', style: WText.button.copyWith(fontSize: 17, color: WColors.ink)),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 6),
      if (word != null) ...[
        _grow(
          3,
          110,
          ChunkyCard(
            color: WColors.card,
            onTap: onFamilyWord,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Expanded(child: Text('FAMILY WORD', maxLines: 1, style: WText.label)),
                  _Chip(
                    text: familyWordData.solved ? 'Found' : '+$kFamilyWordEarlyCoins coins each',
                    color: familyWordData.solved ? WColors.leafTint : WColors.sun,
                  ),
                ]),
                const SizedBox(height: 8),
                Center(
                  child: FamilyWordSlots(
                    word: word,
                    data: familyWordData,
                    players: players,
                    tileSize: 40,
                    colorOf: family == null
                        ? null
                        : (uid) {
                            final m = family.member(uid);
                            return m == null ? null : memberColor(m);
                          },
                  ),
                ),
                const SizedBox(height: 8),
                Text(line, textAlign: TextAlign.center, style: WText.body.copyWith(fontSize: 15)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (family != null) ...[
        _grow(
          3,
          110,
          ChunkyCard(
            color: WColors.sunTint,
            onTap: onFromFamily,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(child: Text('FROM YOUR FAMILY', style: WText.label.copyWith(color: WColors.ink))),
                  if (helpItems.length > 2)
                    Text('+${helpItems.length - 2} more', style: WText.label.copyWith(color: WColors.ink)),
                ]),
                if (helpItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nothing yet today. Letters and cheers from your family show up here.',
                        style: WText.body),
                  )
                else
                  for (final i in helpItems.take(2)) HelpItemRow(item: i, family: family),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      _grow(
        2,
        100,
        Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (family != null) ...[
            Expanded(child: _Square(icon: Icons.map, color: WColors.leaf, label: 'Family map', onTap: onMap)),
            const SizedBox(width: 10),
            Expanded(
              child: _Square(icon: Icons.celebration, color: WColors.coral, label: 'Cheer someone', onTap: onCheer ?? () {}),
            ),
          ] else ...[
            Expanded(child: _Square(icon: Icons.groups, color: WColors.sky, label: 'The family', onTap: onTheFamily)),
            const SizedBox(width: 10),
            Expanded(
              child: _Square(icon: Icons.swap_horiz, color: WColors.lilac, label: 'Pass the phone', onTap: onPassPhone),
            ),
          ],
        ]),
      ),
    ]);
  }
}

class _NoFamilyPage extends StatelessWidget {
  const _NoFamilyPage({required this.onThisPhone, required this.onDifferentPhones});

  final VoidCallback onThisPhone;
  final VoidCallback onDifferentPhones;

  @override
  Widget build(BuildContext context) {
    Widget mystery(double size) => PlayerAvatar(player: const Player(id: '?', name: '?', colorIndex: 5), size: size);
    return _PageBody(children: [
      _grow(
        1,
        220,
        Container(
          margin: const EdgeInsets.only(bottom: WSize.lipHero),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFE59A), WColors.card],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border.all(color: WColors.ink, width: WSize.outline),
            borderRadius: BorderRadius.circular(WSize.radiusHero),
            boxShadow: wLip(WSize.lipHero),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              mystery(52),
              const SizedBox(width: 6),
              const Icon(Icons.groups, size: 64, color: WColors.ink),
              const SizedBox(width: 6),
              mystery(52),
            ]),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text('Play with your family', textAlign: TextAlign.center, style: WText.title.copyWith(fontSize: 30)),
            ),
            const SizedBox(height: 8),
            const Text(
              "Find a family word together, see each other's villages, send letters and cheers.",
              textAlign: TextAlign.center,
              style: WText.body,
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      ChunkyButton(label: 'On this phone', icon: Icons.smartphone, size: ChunkySize.big, expand: true, onPressed: onThisPhone),
      const SizedBox(height: 10),
      ChunkyButton(
        label: 'On different phones',
        icon: Icons.devices,
        size: ChunkySize.big,
        kind: ChunkyKind.secondary,
        expand: true,
        onPressed: onDifferentPhones,
      ),
      const SizedBox(height: 8),
      const Text('Nothing is shared until you say so.', textAlign: TextAlign.center, style: WText.label),
    ]);
  }
}

// ---- Shared pieces --------------------------------------------------------------

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
                : 'Level ${level.level}, ${level.xpIntoLevel} of ${level.xpForNextLevel} XP. Open Me',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: player != null ? onSwitch : onLevel,
              child: Container(
                height: 50,
                margin: const EdgeInsets.only(bottom: WSize.lipSmall),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: WColors.card,
                  border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                  borderRadius: BorderRadius.circular(25),
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
            height: 50,
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

class _VillageCard extends StatefulWidget {
  const _VillageCard({required this.village, required this.onVisit});

  final _Village? village;
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
          // Whatever height the page leaves: the bigger the better.
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Your village', style: WText.title.copyWith(fontSize: 32)),
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
