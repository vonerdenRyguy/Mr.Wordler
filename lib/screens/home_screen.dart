import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/word_runs.dart' show settle;
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
import '../sound/sound_service.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/home_nav.dart';
import '../ui/min_height_box.dart';
import '../ui/tokens.dart';
import '../ui/wallpaper.dart';
import '../explore/fog.dart';
import '../explore/island_map.dart';
import '../village/discovery_journal_view.dart';
import '../village/iso_math.dart';
import '../village/iso_village_view.dart';
import '../village/magic_word.dart';
import '../village/structures.dart';
import '../village/village_art.dart';
import '../village/village_cards.dart';
import '../village/village_save.dart';
import '../village/village_save_migration.dart';
import '../letterra/globe_painter.dart';
import '../letterra/globe_view.dart';
import '../letterra/planet.dart';
import 'daily_challenge_screen.dart';
import 'family_online_screens.dart';
import 'family_screens.dart';
import 'family_word_online_screens.dart';
import 'helping_screens.dart';
import 'town_square_screens.dart';
import 'home_tips.dart';
import 'infinite_estate_screen.dart';
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
  // spec-16: the same fog and outlines as inside the village.
  FogMap? fog,
  List<SpecialMarker> markers,
  // spec-18: where your harbor is on Letterra, your building words (for the
  // little houses on the globe) and how far up you have climbed.
  int slot,
  List<String> words,
  int reach,
  // spec-18: the letters and building runs, for the tiles on the zoomed globe.
  Map<int, String> letters,
  List<({String word, List<int> cells})> runs,
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
    final raw = await VillageSaveController().load();
    if (!mounted || generation != _loadGeneration) return;
    // Shown as it will be once the village opens on Letterra (spec-18); the
    // stored save is only rewritten by the village screen.
    final saved = raw == null
        ? null
        : migrateVillageSave(raw, rackSize: InfiniteEstateScreen.rackSize, planetSlot: raw.planetSlot ?? 0);
    if (saved == null || saved.boardCells.every((c) => c == null)) {
      setState(() => _village = (
            hasSave: saved != null,
            journal: saved?.discoveredWords.length ?? 0,
            buildings: 0,
            scene: null,
            focus: (r: 0, c: 0),
            rack: saved?.rackCells ?? const [],
            discovered: saved?.discoveredWords ?? const {},
            fog: null,
            markers: const [],
            slot: saved?.planetSlot ?? 0,
            words: const [],
            reach: 0,
            letters: const {},
            runs: const [],
          ));
      return;
    }
    const size = InfiniteEstateScreen.boardSize;
    final runs =
        (await settle(saved.boardCells, size, size, ref.read(wordCheckProvider))).settledRuns;
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
      spriteMeta: meta,
    );
    // The same fog and outlines as the village (spec-16): an old save gets its
    // fog worked out the way the village does when it opens.
    final migrated = saved;
    final fog = migrated.cleared == null ? null : FogMap.fromBase64(migrated.cleared!);
    final islandMap = IslandMap.letterra(seed: migrated.mapSeed, slot: migrated.planetSlot ?? 0);
    final markers = [
      for (final sp in islandMap.specials)
        if (sp.kind == SpecialKind.villager ? !migrated.villagers.isMet(sp.id) : !migrated.foundSpecials.contains(sp.id))
          SpecialMarker(sp.cell, sp.kind),
    ];
    setState(() => _village = (
          hasSave: true,
          journal: saved.discoveredWords.length,
          buildings: structures.length,
          scene: scene,
          focus: _focusOf(scene, saved.discoveredWords),
          rack: saved.rackCells,
          discovered: saved.discoveredWords,
          fog: fog,
          markers: markers,
          slot: migrated.planetSlot ?? 0,
          words: [for (final s in structures) s.def.word],
          reach: fog == null ? 1 : reachFromFog(fog, migrated.planetSlot ?? 0),
          letters: {
            for (var i = 0; i < saved.boardCells.length; i++)
              if (saved.boardCells[i] != null) i: saved.boardCells[i]!,
          },
          runs: [for (final st in structures) (word: st.def.word, cells: st.ordered)],
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
    await claimFamilyCoins(ref, context);
    if (mounted) celebrateSquare(ref, context);
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

  // The measured heights of the floating top bar and bottom bars.
  double? _chromeTop;
  double? _chromeBottom;

  void _setChrome({double? top, double? bottom}) {
    if (!mounted) return;
    final t = top ?? _chromeTop, b = bottom ?? _chromeBottom;
    if (t == _chromeTop && b == _chromeBottom) return;
    setState(() {
      _chromeTop = t;
      _chromeBottom = b;
    });
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
    // A Town Square building finished (spec-13): We built it! and coins.
    ref.listen(familyOnlineProvider.select((s) => s.square?.built.length), (_, n) {
      // Not in the middle of a game: it waits until Home is back on top.
      if (n != null && (ModalRoute.of(context)?.isCurrent ?? true)) celebrateSquare(ref, context);
    });
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
      Wallpaper(
        kind: WallpaperKind.hills,
        child: _MePage(
        level: level,
        player: players.current,
        wordOfDay: wordOfDay,
        wordClaimed: wordClaimed,
        wordLevel: wordLevel,
        onLevel: () => _open(const PortfolioScreen()),
        onWordOfDay: wordOfDay == null ? null : () => _openWordOfDay(wordOfDay, wordClaimed),
        onJournal: _openJournal,
        onVillagers: () => _open(const InfiniteEstateScreen(openVillagers: true)),
        onProperties: () => _open(const PortfolioScreen()),
        onStats: () => _open(const StatsScreen()),
        onWordLevel: () => _open(const WordLevelScreen()),
      ),
      ),
      _PlayPage(
        village: _village,
        playedToday: playedToday,
        streak: daily.streak,
        theme: dailyPuzzleFor(now).theme.name,
        wordLevel: wordLevel,
        now: now,
        playerName: players.current.name,
        onVisit: () => _open(const InfiniteEstateScreen()),
        onDaily: () => _openDaily(playedToday),
      ),
      if (!hasFamily)
        Wallpaper(
          kind: WallpaperKind.pattern,
          child: _NoFamilyPage(
          onThisPhone: () => _open(const FamilyScreen()),
          onDifferentPhones: () => _open(const FamilyOnlineScreen()),
        ),
        )
      else if (onlineFamily != null)
        TownSquarePage(
          streak: familyWordData.solved ? familyWordData.streak : 0,
          familyWordAlert: !playedToday && !familyWordData.solved,
          helpCount: helpItems.length,
          onFamilyWord: () => _open(const FamilyWordScreen()),
          onFromFamily: () => _open(const FromFamilyScreen()),
        )
      else
        Wallpaper(
          kind: WallpaperKind.pattern,
          child: _FamilyPage(
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
        ),
    ];

    // Until the floating bars have been measured, a close guess.
    final mq = MediaQuery.of(context);
    final scale = mq.textScaler.scale(1.0);
    final chromeTop = _chromeTop ?? mq.padding.top + 16 + 54 * scale;
    final chromeBottom = _chromeBottom ?? mq.padding.bottom + 86 + (shownTip != null ? 56 * scale : 0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        backgroundColor: WColors.paper,
        // The pages fill the screen and the top bar, tip, dots and tabs
        // float over them (spec-12), so Play's village runs edge to edge.
        // Each page keeps clear of them through MediaQuery's padding.
        body: Stack(
          children: [
            Positioned.fill(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(padding: EdgeInsets.only(top: chromeTop, bottom: chromeBottom)),
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) {
                    ref.read(soundProvider).play(Sfx.whoosh);
                    setState(() => _page = i);
                  },
                  children: pages,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _ChromeBackdrop(
                pages: _pages,
                page: _page,
                top: true,
                child: _ReportSize(
                  onSize: (s) => _setChrome(top: s.height),
                  child: SafeArea(
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
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ReportSize(
                onSize: (s) => _setChrome(bottom: s.height),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ChromeBackdrop(
                      pages: _pages,
                      page: _page,
                      top: false,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                      ]),
                    ),
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
              ),
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
    // Clear of the floating top bar and bottom bars.
    final pad = MediaQuery.paddingOf(context);
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(WSize.screenPadding, pad.top + 8, WSize.screenPadding, pad.bottom + 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

/// The page's wallpaper behind the floating bars on Me and Family (the
/// same picture, lined up with the screen), so a page that scrolls at big
/// text never shows through; clear over Play's village. Fades with the
/// swipe.
class _ChromeBackdrop extends StatelessWidget {
  const _ChromeBackdrop({required this.pages, required this.page, required this.top, required this.child});

  final PageController pages;
  final int page;
  // At the top of the screen (else the bottom).
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pages,
      builder: (context, child) {
        final at = pages.hasClients && pages.positions.length == 1 ? (pages.page ?? page.toDouble()) : page.toDouble();
        final cover = (at - HomePage.play.index).abs().clamp(0.0, 1.0);
        final kind = at < HomePage.play.index ? WallpaperKind.hills : WallpaperKind.pattern;
        return Stack(children: [
          if (cover > 0)
            Positioned.fill(
              child: Opacity(
                opacity: cover,
                child: WallpaperSlice(kind: kind, top: top, child: const SizedBox.expand()),
              ),
            ),
          child!,
        ]);
      },
      child: child,
    );
  }
}

/// Tells [onSize] its child's size after each layout that changes it.
class _ReportSize extends SingleChildRenderObjectWidget {
  const _ReportSize({required this.onSize, required Widget child}) : super(child: child);

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderReportSize(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderReportSize renderObject) => renderObject.onSize = onSize;
}

class _RenderReportSize extends RenderProxyBox {
  _RenderReportSize(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
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

/// Play (spec-18): the planet Letterra turned to your harbor. Tap your
/// village to go in; the Daily is a round badge. A goal bar says how far you
/// have climbed toward the Great Lantern.
class _PlayPage extends ConsumerStatefulWidget {
  const _PlayPage({
    required this.village,
    required this.playedToday,
    required this.streak,
    required this.theme,
    required this.wordLevel,
    required this.now,
    required this.playerName,
    required this.onVisit,
    required this.onDaily,
  });

  final _Village? village;
  final bool playedToday;
  final int streak;
  final String theme;
  final WordLevel wordLevel;
  final DateTime now;
  final String playerName;
  final VoidCallback onVisit;
  final VoidCallback onDaily;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  ConsumerState<_PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends ConsumerState<_PlayPage> {
  int? _focus;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final v = widget.village;
    final mySlot = v?.slot ?? 0;
    final focus = _focus ?? mySlot;
    final reduce = ref.watch(settingsProvider).reduceMotion;
    final info = v == null || !v.hasSave
        ? 'New village'
        : '${v.buildings} building${v.buildings == 1 ? '' : 's'} · Journal ${v.journal}/${kMagicWords.length}';
    final reach = v?.reach ?? 1;
    final villages = [
      GlobeVillage(
        slot: mySlot,
        name: widget.playerName,
        buildings: (v?.words ?? const <String>[]).take(4).toList(),
        reach: reach,
        letters: v?.letters ?? const {},
        buildingRuns: v?.runs ?? const [],
      ),
    ];
    final taken = {for (final g in villages) g.slot};
    final fog = v?.fog;
    bool hushed(int row, int col, double lon) {
      // Each slice follows the nearest filled harbor: yours by your fog.
      if (fog != null) return !fog.isCleared(row * kPlanetBoard + col);
      return hushedByReach(row, col, reach);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFBFE6F5)),
        // The planet fills what the bars leave; the badge and goal sit under it.
        Padding(
          padding: EdgeInsets.fromLTRB(0, pad.top, 0, pad.bottom + 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GlobeView(
                  villages: villages,
                  takenSlots: taken,
                  focusSlot: focus,
                  isHushed: hushed,
                  reduceMotion: reduce,
                  onVillageTap: (_) => widget.onVisit(),
                  onTurn: (s) => setState(() => _focus = s),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: WSize.screenPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RoundBadge(
                          label: 'Daily puzzle',
                          semantics: 'Daily puzzle. ${widget.playedToday ? 'Done for today' : 'Not played yet'}'
                              '${widget.streak >= 2 ? '. ${widget.streak}-day streak' : ''}',
                          color: WColors.sky,
                          alert: !widget.playedToday,
                          sub: widget.streak >= 2 ? '${widget.streak}-day streak' : null,
                          onTap: widget.onDaily,
                          child: _CalendarTile(month: _PlayPage._months[widget.now.month - 1], day: widget.now.day),
                        ),
                      ],
                    ),
                    const SizedBox(height: WSize.gap3),
                    _GoalBar(
                      title: 'Light the Great Lantern',
                      sub: 'You reached ${reachName(reach)} · tap your village to go in',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // A soft shade at the top so the floating bits read well.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33000000), Color(0x00000000), Color(0x00000000)],
                stops: [0, 0.14, 1],
              ),
            ),
          ),
        ),
        Positioned(
          top: pad.top + 6,
          left: WSize.screenPadding,
          right: WSize.screenPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(child: _FloatChip(text: info)),
              const Spacer(),
              _Chip(text: widget.wordLevel.info.name, color: widget.wordLevel.info.color),
            ],
          ),
        ),
      ],
    );
  }
}

/// The goal line at the bottom of Play.
class _GoalBar extends StatelessWidget {
  const _GoalBar({required this.title, required this.sub});

  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: WColors.card,
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: BorderRadius.circular(WSize.radiusHero),
        boxShadow: wLip(WSize.lip),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, maxLines: 1, style: WText.heading.copyWith(fontSize: 22, color: WColors.ink)),
        Text(sub, textAlign: TextAlign.center, style: WText.bodyBold.copyWith(fontSize: 16, color: WColors.ink)),
      ]),
    );
  }
}

/// A small label floating over the village.
class _FloatChip extends StatelessWidget {
  const _FloatChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: WColors.card.withOpacity(0.92),
        borderRadius: BorderRadius.circular(WSize.radiusChip),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: WText.label.copyWith(color: WColors.ink)),
    );
  }
}

/// A round game badge over the village, with its name under it and an
/// optional red "!" (not played yet today).
class _RoundBadge extends StatefulWidget {
  const _RoundBadge({
    required this.label,
    required this.semantics,
    required this.color,
    required this.onTap,
    required this.child,
    this.alert = false,
    this.sub,
  });

  final String label;
  final String semantics;
  final Color color;
  final VoidCallback onTap;
  final Widget child;
  final bool alert;
  final String? sub;

  @override
  State<_RoundBadge> createState() => _RoundBadgeState();
}

class _RoundBadgeState extends State<_RoundBadge> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const size = 84.0;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: widget.semantics,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          playSfx(context, Sfx.tap);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed && !reduce ? 0.92 : 1,
          duration: const Duration(milliseconds: 90),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: WColors.ink, width: WSize.outline),
                      boxShadow: wLip(WSize.lip),
                    ),
                    child: widget.child,
                  ),
                  if (widget.alert)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: WColors.brick,
                          shape: BoxShape.circle,
                          border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                        ),
                        child: Text('!',
                            textScaler: TextScaler.noScaling,
                            style: WText.button.copyWith(color: WColors.white, fontSize: 18)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _FloatChip(text: widget.label),
              if (widget.sub != null) ...[
                const SizedBox(height: 4),
                _FloatChip(text: widget.sub!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarTile extends StatelessWidget {
  const _CalendarTile({required this.month, required this.day});

  final String month;
  final int day;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: WColors.white,
        border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Container(
          width: double.infinity,
          color: WColors.brick,
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(month,
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              style: WText.buttonSmall.copyWith(fontSize: 11, color: WColors.white)),
        ),
        Expanded(
          child: Center(
            child: Text('$day',
                textScaler: TextScaler.noScaling, style: WText.number.copyWith(fontSize: 24, color: WColors.ink)),
          ),
        ),
      ]),
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
    required this.onVillagers,
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
  final VoidCallback onVillagers;
  final VoidCallback onProperties;
  final VoidCallback onStats;
  final VoidCallback onWordLevel;

  @override
  Widget build(BuildContext context) {
    final toNext = (level.xpForNextLevel - level.xpIntoLevel).clamp(0, 1 << 30);
    final word = wordOfDay;
    // A profile, like a game's (spec-12b): you in the middle, one strip,
    // one row of round buttons.
    return _PageBody(children: [
      const Spacer(flex: 2),
      Semantics(
        button: true,
        label: '${player.name}. Level ${level.level}. $toNext points to Level ${level.level + 1}. Open My properties',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLevel,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 150,
              height: 150,
              child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: level.progress,
                    strokeWidth: 12,
                    color: WColors.grass,
                    backgroundColor: WColors.boardCell,
                  ),
                ),
                PlayerAvatar(player: player, size: 112),
                Positioned(
                  bottom: -14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    decoration: BoxDecoration(
                      color: WColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: WColors.ink, width: WSize.outline),
                      boxShadow: wLip(WSize.lipSmall),
                    ),
                    child: Text('Level ${level.level}', style: WText.button.copyWith(color: WColors.ink)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Text(player.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: WText.heading.copyWith(fontSize: 30)),
            Text('$toNext points to Level ${level.level + 1}', style: WText.label),
          ]),
        ),
      ),
      const Spacer(),
      Semantics(
        button: word != null,
        label: word == null
            ? 'Word of the day'
            : 'Word of the day: ${word.word}. ${wordClaimed ? 'Done' : 'Spell it in your village for $kWordOfDayCoins coins'}. Open.',
        excludeSemantics: true,
        child: ChunkyCard(
          color: WColors.card,
          onTap: onWordOfDay,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: WColors.leafTint,
                shape: BoxShape.circle,
                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
              ),
              child: const Icon(Icons.eco, color: WColors.grass, size: 26),
            ),
            const SizedBox(width: WSize.gap3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Word of the day', maxLines: 1, style: WText.label),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(word?.word ?? '',
                      maxLines: 1, style: WText.heading.copyWith(fontSize: 26, letterSpacing: 2)),
                ),
              ]),
            ),
            if (word != null)
              _Chip(
                text: wordClaimed ? 'Done' : '+$kWordOfDayCoins',
                color: wordClaimed ? WColors.card : WColors.sun,
              ),
          ]),
        ),
      ),
      const Spacer(),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoundButton(icon: Icons.menu_book, color: WColors.skyTint, label: 'Journal', onTap: onJournal),
          _RoundButton(icon: Icons.people, color: WColors.sunTint, label: 'Villagers', onTap: onVillagers),
          _RoundButton(icon: Icons.home_work, color: WColors.leafTint, label: 'Homes', onTap: onProperties),
          _RoundButton(icon: Icons.bar_chart, color: WColors.coralTint, label: 'Stats', onTap: onStats),
          _RoundButton(
            icon: Icons.school,
            color: wordLevel.info.color,
            label: 'Word level',
            semantics: 'Word level: ${wordLevel.info.name}',
            onTap: onWordLevel,
          ),
        ],
      ),
      const Spacer(),
    ]);
  }
}

/// A round button with a word under it (Me's row, spec-12b).
class _RoundButton extends StatefulWidget {
  const _RoundButton({required this.icon, required this.color, required this.label, required this.onTap, this.semantics});

  final IconData icon;
  final Color color;
  final String label;
  final String? semantics;
  final VoidCallback onTap;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: widget.semantics ?? widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          playSfx(context, Sfx.tap);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed && !reduce ? 0.92 : 1,
          duration: const Duration(milliseconds: 90),
          child: SizedBox(
            width: 70,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 60,
                height: 60,
                margin: const EdgeInsets.only(bottom: WSize.lip),
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: WColors.ink, width: WSize.outline),
                  boxShadow: wLip(WSize.lip),
                ),
                child: Icon(widget.icon, size: 32, color: WColors.ink),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: WText.buttonSmall.copyWith(color: WColors.ink, fontSize: 16)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A big square button: a round picture and a word or two under it.
class _Square extends StatelessWidget {
  const _Square({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
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
