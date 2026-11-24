import 'dart:math' as math;

import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../daily/word_of_the_day.dart';
import '../daily/word_of_the_day_controller.dart';
import '../dictionary/definition_service.dart';
import '../explore/explore_rules.dart';
import '../explore/fog.dart';
import '../explore/island_map.dart';
import '../letterra/band_info.dart';
import '../explore/regions.dart';
import '../letterra/close_up.dart' show kCloseUpMaxZoom;
import '../letterra/globe_painter.dart';
import '../letterra/globe_view.dart';
import '../letterra/planet_data.dart';
import '../letterra/something_to_find.dart';
import '../letterra/street.dart';
import '../players/players.dart';
import '../letterra/gold_star.dart';
import '../letterra/planet.dart';
import '../letterra/port.dart';
import '../letterra/port_view.dart';
import '../portfolio/level_info.dart';
import '../settings/settings_controller.dart' show settingsProvider;
import 'island_map_screen.dart';
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_game_state.dart';
import '../game/grid_providers.dart';
import '../game/word_landing.dart' show startCellProvider, wordCheckProvider;
import '../game/word_runs.dart';
import '../online/family_online_controller.dart';
import 'family_screens.dart' show VisitVillageScreen;
import 'helping_screens.dart' show showGiftsArrived;
import 'planet_bottom.dart';
import '../portfolio/portfolio_controller.dart';
import '../stats/mode_stats_controller.dart';
import '../village/bridge_transform.dart';
import '../village/discovery_journal_view.dart';
import '../village/iso_math.dart';
import '../village/iso_village_view.dart';
import '../village/magic_word.dart';
import '../village/structures.dart';
import '../village/village_art.dart';
import '../village/village_cards.dart';
import '../village/village_rewards.dart';
import '../village/village_save.dart';
import '../village/village_save_migration.dart';
import '../villagers/village_book.dart';
import '../villagers/villager_look.dart';
import '../villagers/walkers.dart';
import '../villagers/villager_names.dart';
import '../villagers/wish.dart';
import '../settings/word_level.dart' show WordLevel;
import 'villagers_screens.dart';

import '../ui/chunky_button.dart';
import '../ui/letter_bag.dart';
import '../sound/sound_service.dart';
import '../ui/pill_chip.dart';
import '../ui/reward_moment.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import '../ui/wordler_scaffold.dart';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ViewMode { words, planet }

// Infinite Estate / Village Builder: an endless-feeling session on a large
// (500x500, pannable/zoomable) board -- not literally unbounded, but big
// enough that a normal session never reaches an edge, with the same zoom
// feel as every other mode's board and generous pan range so the space
// reads as open rather than a small fixed grid. The rack refills itself
// the instant a tile leaves it for the board (GridConfig.refillRackOnPlace),
// with balanced draws (GridConfig.balancedRefill) so it never jams; a
// "Swap letters" button trades the whole unpinned rack for coins.
//
// 500x500 = 250,000 cells -- far too many to build eagerly (see every
// other mode's GridBoardView, which does exactly that and is fine at
// 10x10). Instead the board is rendered lazily via
// InteractiveViewer.builder: only cells that actually intersect the
// current viewport are ever built (see GridBoardView.cellSize), so
// panning/zooming stays smooth regardless of how much of the estate has
// been explored.
//
// The village persists across sessions: the board is saved after every
// change and restored on open, so structures a player builds stay built.
// There's no win condition -- "End Session" just cashes out the score
// growth since the last cash-out into currency/XP and lets the player
// leave; the village itself is never reset.
class InfiniteEstateScreen extends StatelessWidget {
  const InfiniteEstateScreen({
    super.key,
    this.openVillagers = false,
    this.focusCell,
    this.startOnPlanet = false,
    this.planet,
  });

  /// Open on the planet (a tap on Home's) instead of on Words.
  final bool startOnPlanet;

  /// Home's planet: the other players' villages, and yours until it has loaded.
  final ValueListenable<PlanetData?>? planet;

  /// Open looking at this board square (planet mode's Show me).
  final int? focusCell;

  /// Open straight onto the Your villagers page (Me's shortcut, spec-18).
  final bool openVillagers;

  static const int boardSize = 500;
  // 10 big tiles in 2 rows of 5 (was 21). Saves from the 21-tile days are
  // migrated on load -- see village_save_migration.dart.
  static const int rackSize = 10;
  static const int swapCost = 5;
  // Fixed on-screen size (at zoom scale 1.0) of one board cell, in logical
  // pixels -- see GridBoardView.cellSize. Chosen to be comfortably
  // tappable without the lazily-built board needing to know anything
  // about the viewport's own dimensions.
  static const double cellSize = 44.0;
  // Board centre cell index: the village starts here and the island map
  // is seeded around it.
  static const int homeIndex = boardSize ~/ 2 * boardSize + boardSize ~/ 2;
  // Comfortably more than a long session will draw through; the letter
  // pool repeats its weighted distribution to cover any size (see
  // LetterGenerator.generateLetters), so this just needs to be "a lot".
  static const int totalPoolSize = 3000;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        gridConfigProvider.overrideWithValue(
          const GridConfig(
            boardWidth: boardSize,
            boardHeight: boardSize,
            rackSize: rackSize,
            totalPoolSize: totalPoolSize,
            refillRackOnPlace: true,
            balancedRefill: true,
          ),
        ),
        startCellProvider.overrideWith((ref) => null),
      ],
      child: _InfiniteEstateBody(
        openVillagers: openVillagers,
        focusCell: focusCell,
        startOnPlanet: startOnPlanet,
        planet: planet,
      ),
    );
  }
}

// A grass field with no grid lines, so Infinite Estate reads as "open
// land" at a glance.
const _estateTheme = GridTheme(
  boardColor: WColors.grassFieldCell,
  boardBorderColor: WColors.grassFieldCell, // no grid lines on the field
  rackColor: WColors.soilDeep,
);

// Weights a set of currently-valid board words by length x letter rarity.
int scoreForWords(List<String> words) {
  int total = 0;
  for (final word in words) {
    int letterScore = 0;
    for (final rune in word.split('')) {
      letterScore += LetterGenerator.letterPoints[rune] ?? 0;
    }
    total += letterScore * word.length;
  }
  return total;
}

class _InfiniteEstateBody extends ConsumerStatefulWidget {
  const _InfiniteEstateBody({this.openVillagers = false, this.focusCell, this.startOnPlanet = false, this.planet});

  final bool startOnPlanet;
  final ValueListenable<PlanetData?>? planet;

  final int? focusCell;

  final bool openVillagers;

  @override
  ConsumerState<_InfiniteEstateBody> createState() => _InfiniteEstateBodyState();
}

class _InfiniteEstateBodyState extends ConsumerState<_InfiniteEstateBody>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin
    implements VillagerHost {
  int _score = 0;
  // Score value already paid out as currency/XP -- End Session only
  // rewards growth past this, so re-visiting an unchanged village and
  // ending again doesn't re-pay the same structures.
  int _lastCashedOutScore = 0;
  late _ViewMode _viewMode = widget.startOnPlanet ? _ViewMode.planet : _ViewMode.words;
  List<BoardStructure> _structures = [];
  bool _computingStructures = false;

  final _saveController = VillageSaveController();
  bool _restoring = true;

  // ── spec-15 explore state ────────────────────────────────────────────────
  late IslandMap _islandMap;
  FogMap _fog = FogMap.empty(); // replaced once the save loads
  int _mapSeed = VillageSaveData.kDefaultMapSeed;
  // spec-18: the harbor spot this village sits on, and (for a moved village)
  // the save version it came from.
  int _slot = 0;
  int? _migratedFrom;
  int get _harborIndex => harborCell(_slot);

  // spec-18b: a brand-new village's first word must cover the gold star.
  bool _starStart = false;
  bool _starDone = false;
  bool get _starActive => _starStart && !_starDone;
  late int _starCell = _harborIndex;
  Set<int> _offStarCells = const {};
  // Regions already celebrated (see regions.dart).
  Set<int>? _bandsReached;
  // An older save's first visit fills them in without a word.
  bool _bandsQuiet = false;
  // The port, worked out again only when the letters change.
  Port? _port;
  List<String?>? _portBoard;

  Port _portNow() {
    final board = ref.read(gridGameControllerProvider).boardCells;
    if (_port == null || !identical(board, _portBoard)) {
      _portBoard = board;
      _port = portFor(_slot, [
        for (var i = 0; i < board.length; i++)
          if (board[i] != null) i,
      ]);
    }
    return _port!;
  }

  void _placeStar() {
    if (!_starStart) return;
    _starCell = goldStarCell(_slot,
        isSea: _islandMap.isSeaIndex, taken: {for (final s in _islandMap.specials) s.cell});
    ref.read(startCellProvider.notifier).state = _starActive ? _starCell : null;
  }
  int _mapVersion = VillageSaveData.kDefaultMapVersion;
  Set<int> _everUsed = {};
  Set<String> _everWords = {};
  Set<String> _foundSpecials = {};
  Set<ShrineKind> _shrines = {};
  Set<int> _levelTreats = {};
  // spec-16: the villagers who have moved in. A notifier so the card and the
  // Your villagers page update live; saved with the village.
  final ValueNotifier<VillagerBook> _bookNotifier = ValueNotifier(const VillagerBook());
  VillagerBook get _book => _bookNotifier.value;
  final VillagerWalkers _walkers = VillagerWalkers();
  Set<int> _reachedLandmarks = {};
  Set<String> _discoveredWords = {};
  // Rack pinning is a pure UI affordance (no mechanical effect), so it's
  // deliberately not persisted -- it's about tracking intent within a
  // single visit, not a permanent record.
  final Set<int> _pinnedRackIndices = {};
  // Rack slots holding a letter gift from the family this visit (spec-10),
  // shown with a gold stripe. Like pins, not saved.
  Set<int> _giftRackIndices = {};

  // Well structure ability: one free bonus letter draw per visit to the
  // village (not per session-open -- reopening the app doesn't reset it,
  // since that would just be a way to farm free letters). Session-only,
  // not persisted.
  bool _wellUsedThisVisit = false;
  // Free Swaps used this visit (1 each visit, 2 with a Farm). Works like
  // the Well's limit: session-only, reset when the screen is reopened.
  int _freeSwapsUsed = 0;

  // Bridge structure ability: drives GridBoardView's InteractiveViewer to
  // jump/pan to a reached landmark. _boardViewportSize is captured by the
  // LayoutBuilder wrapping the board area and used to compute the jump
  // transform (see bridge_transform.dart) -- it's only known once that
  // area has actually been laid out, hence nullable.
  final _transformController = TransformationController();
  // The planet (spec-22): made afresh each time it opens, looking at
  // [_planetCell] (null: the whole planet).
  GlobalKey<GlobeViewState> _globe = GlobalKey<GlobeViewState>();
  int? _planetCell;
  double _planetZoom = 1;
  // Flying down to another village, or a new building landing.
  bool _planetBusy = false;
  PlanetData? _planetData;
  List<Object?> _planetKey = const [];
  List<GroundMark> _planetMarks = const [];
  // A new building dropping into place.
  ({List<int> cells, double t})? _drop;
  late final AnimationController _dropAnim;
  static const _isoGrid =
      IsoGrid(boardWidth: InfiniteEstateScreen.boardSize, boardHeight: InfiniteEstateScreen.boardSize);
  // Rebuilt only when the board or the buildings change.
  VillageScene? _scene;
  List<String?>? _sceneBoard;
  List<BoardStructure>? _sceneStructures;
  Map<String, SpriteMeta> _spriteMeta = const {};
  // Every valid word on the board (repeats included), for tap cards.
  List<WordRun> _wordRuns = const [];
  // spec-17: runs that aren't words, and letters that aren't settled.
  List<WordRun> _badRuns = const [];
  Set<int> _looseCells = const {};
  // Loose letters that are in no real word at all: the only ones tidied away.
  Set<int> _strayCells = const {};
  // Words standing when the real-words rule arrived (see settle's `kept`).
  List<WordRun> _keptRuns = const [];
  // spec-17: an old village is tidied once; the note about letters Mr. W put
  // back waits here (and in the save) until the player has seen it.
  bool _tidiedLoose = true;
  // The latest board/rack/pool, kept so leaving can save without touching ref
  // (which dispose() may not use).
  GridGameState? _lastGrid;
  int _looseNote = 0;
  // The word whose card is open, lit up on the map.
  Set<int> _highlight = const {};
  Size? _boardViewportSize;
  // The board is far too large to show all at once, so the very first
  // frame instead centers the view on the village's origin (the board's
  // center -- the same point landmark.dart spreads landmarks out from)
  // rather than defaulting to InteractiveViewer's identity transform,
  // which would leave a fresh player looking at the board's empty
  // top-left corner. Set once; the player's own panning/zooming after
  // that is never overridden.
  bool _viewCentered = false;

  @override
  void initState() {
    super.initState();
    _dropAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    initSpellCheck();
    WidgetsBinding.instance.addObserver(this);
    _islandMap = IslandMap.letterra(seed: _mapSeed, slot: _slot);
    _loadSavedVillage();
    VillageArt.loadMeta().then((meta) {
      if (mounted) setState(() => _spriteMeta = meta);
    }).catchError((_) {});
  }

  VillageScene _villageScene() {
    final board = ref.read(gridGameControllerProvider).boardCells;
    if (_scene == null ||
        !identical(board, _sceneBoard) ||
        !identical(_structures, _sceneStructures) ||
        !identical(_scene!.spriteMeta, _spriteMeta)) {
      _sceneBoard = board;
      _sceneStructures = _structures;
      _scene = VillageScene(
        grid: _isoGrid,
        boardCells: board,
        structures: _structures,
        spriteMeta: _spriteMeta,
      );
    }
    return _scene!;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTidiedForLeaving();
    _transformController.dispose();
    _dropAnim.dispose();
    _bookNotifier.dispose();
    _walkers.dispose();
    super.dispose();
  }

  bool _hasStructure(String magicWord) => _structures.any((s) => s.def.word == magicWord);

  // spec-15: returns a fog overlay color for a board cell index.
  //   - Solid fog (can't see): dark grey, mostly opaque.
  //   - Fuzzy edge (canSee but not cleared): lighter grey, semi-transparent.
  //   - Cleared: null (no overlay); water cells get a subtle blue tint.
  Color? _fogOverlay(int index) {
    final port = _portNow();
    if (index == port.boat || port.pier.contains(index)) return const Color(0x99286FA8);
    if (!_fog.isCleared(index)) {
      if (_fog.canSee(index)) return const Color(0x55888888); // edge haze
      return const Color(0xCC555555); // solid fog
    }
    // spec-18: open sea is blue; a letter standing in it is a pier (wood).
    if (_islandMap.isSeaIndex(index)) {
      return ref.read(gridGameControllerProvider).boardCells[index] != null
          ? const Color(0x88805A2A)
          : const Color(0x99286FA8);
    }
    // Subtle ring tint for cleared cells (water = blue; others uncolored).
    if (_islandMap.isWaterIndex(index)) return const Color(0x44448BCA);
    return null;
  }

  // spec-15: golden special tile cells, for the XP multiplier.
  late final Set<int> _goldenCells = {
    for (final s in _islandMap.specials)
      if (s.kind == SpecialKind.goldenSquare) s.cell,
  };

  // spec-15: process fog clearing, XP, and special tile activation after
  // any board change. Called from _refreshStructures once currentWordRuns
  // has the latest valid words.
  //
  // - Clears fog around any run that satisfies wordClearsFog.
  // - Awards XP for newly-covered cells (via xpFor from explore_rules.dart).
  // - Activates special tiles that sit under any new cell:
  //     treasure chest  → 20 coins
  //     golden square   → marks the cell as golden (boosts XP formula)
  //     shrine          → unlocks the shrine kind (ability visible in later commits)
  //     boulder/landmark → noted in foundSpecials (rewards in later commits)
  // - Updates _everUsed and _everWords so each reward fires only once.
  Future<void> _processExploreRewards(List<WordRun> runs) async {
    if (runs.isEmpty) return;
    final level = ref.read(settingsProvider).wordLevel;
    final radius = clearRadius(level);

    var fogChanged = false;
    var newXp = 0;
    var newCoins = 0;
    final newlyActivated = <String>[];

    for (final run in runs) {
      final newCells = run.positions.where((p) => !_everUsed.contains(p)).toList();
      if (newCells.isEmpty) continue;

      // ── XP ──────────────────────────────────────────────────────────────
      newXp += xpFor(
        run: run,
        everUsed: _everUsed,
        everWords: _everWords,
        goldenCells: _goldenCells,
        hasGoldenLetter: false, // golden letter tiles tracked in a later commit
      );

      // ── Fog clearing ────────────────────────────────────────────────────
      final clears = wordClearsFog(
        run,
        ringAt: _islandMap.ringAtIndex,
        isWater: _islandMap.isWaterIndex,
        level: level,
      );
      if (clears) {
        final before = _fog.clearedCount;
        _fog = _fog.clearAround(run.positions, radius: radius);
        if (_fog.clearedCount != before) fogChanged = true;
      }

      // ── Specials ────────────────────────────────────────────────────────
      for (final cell in newCells) {
        final special = _islandMap.specialAt(cell);
        if (special == null) continue;
        if (special.kind == SpecialKind.villager) continue; // spec-16: the villager book handles them
        if (_foundSpecials.contains(special.id)) continue;
        _foundSpecials = {..._foundSpecials, special.id};
        newlyActivated.add(special.id);
        switch (special.kind) {
          case SpecialKind.chest:
            newCoins += 20;
          case SpecialKind.goldenSquare:
            _goldenCells.add(cell); // already there, but ensures mutable set
          case SpecialKind.boulder:
            newXp += 10;
          case SpecialKind.landmark:
            newCoins += 50;
          case SpecialKind.shrine:
            final kind = special.shrine!;
            _shrines = {..._shrines, kind};
          case SpecialKind.villager:
            break;
        }
      }

      // ── Track usage ─────────────────────────────────────────────────────
      _everUsed = {..._everUsed, ...run.positions};
      _everWords = {..._everWords, run.word};
    }

    if (newXp <= 0 && newCoins <= 0 && !fogChanged && newlyActivated.isEmpty) return;

    final portfolio = ref.read(portfolioProvider);
    final levelBefore = levelInfoForXp(portfolio.totalXp).level;
    if (newXp > 0) {
      ref.read(portfolioProvider.notifier).addXp(newXp);
      _showXpFloat(newXp);
    }
    if (newCoins > 0) ref.read(portfolioProvider.notifier).addCurrency(newCoins);
    if (fogChanged) setState(() {}); // redraw fog overlay
    final reached = fogChanged ? regionsCleared(_fog).difference(_bandsReached ?? const {}) : const <int>{};
    _bandsReached = {...?_bandsReached, ...reached};
    final celebrate = reached.isNotEmpty && !_bandsQuiet;
    if (celebrate) {
      ref.read(portfolioProvider.notifier).addCurrency(kRegionCoins * reached.length);
    }
    await _saveVillage();
    if (celebrate) await _celebrateRegion(reached);
    if (!mounted) return;

    // Level-up treats (fire at most once per level, in order).
    if (newXp > 0) {
      final levelAfter = levelInfoForXp(ref.read(portfolioProvider).totalXp).level;
      for (var lv = levelBefore + 1; lv <= levelAfter; lv++) {
        if (!_levelTreats.contains(lv)) await _doLevelTreat(lv);
      }
    }
  }

  // The first time cleared land reaches a region (spec-18b); already paid.
  Future<void> _celebrateRegion(Set<int> reached) async {
    await _rewardsShowing;
    if (!mounted) return;
    final furthest = reached.reduce(math.max);
    _rewardsShowing = showRewardMoment(
      context,
      ribbon: 'New region!',
      title: 'You reached ${reachName(furthest)}!',
      message: 'New land, and new things to find.',
      coins: kRegionCoins * reached.length,
    );
    await _rewardsShowing;
  }

  // ── spec-16 villagers ────────────────────────────────────────────────────

  void _setBook(VillagerBook book) {
    if (!mounted) return;
    setState(() => _bookNotifier.value = book);
    _syncWalkers();
    _saveVillage();
  }

  // Tells the walkers who lives where and which slabs they may use.
  void _syncWalkers() {
    if (!mounted) return;
    _walkers.sync({for (final v in _book.villagers) v.id: v.cell}, _villageScene().walkable);
  }

  // The rings the player can already see (fog cleared somewhere), for wishes
  // about places. Looks at the area around home, where all the rings are.
  Set<Ring> _seenRings() {
    const bw = InfiniteEstateScreen.boardSize;
    final homeR = _harborIndex ~/ bw;
    final homeC = _harborIndex % bw;
    final seen = <Ring>{};
    for (var dr = -110; dr <= 110 && seen.length < 4; dr += 2) {
      for (var dc = -110; dc <= 110; dc += 2) {
        if (homeR + dr < 0 || homeR + dr >= bw || homeC + dc < 0 || homeC + dc >= bw) continue;
        final idx = (homeR + dr) * bw + homeC + dc;
        if (!_fog.isCleared(idx)) continue;
        seen.add(_islandMap.ringAtIndex(idx));
      }
    }
    return seen;
  }

  Wish _newWishFor(int homeCell, List<WordRun> runs, {Wish? previous}) {
    return chooseWish(
      ref.read(settingsProvider).wordLevel,
      math.Random(),
      seenRings: _seenRings(),
      previous: previous,
      alreadyMet: (w) => runs.any((r) => wishMetBy(w, r, homeCell: homeCell, ringAt: _islandMap.ringAtIndex)),
    );
  }

  // Villagers: anyone whose square now holds a letter of a real word moves
  // in; wishes whose day has come arrive; wishes the board now answers come
  // true. All three work from the words on the board, so an older village
  // (or a word that was already there) counts too.
  Future<void> _processVillagers(List<WordRun> runs) async {
    // 1. Move in.
    for (final tile in _islandMap.villagers) {
      if (_book.isMet(tile.id)) continue;
      // A word of 3+ letters, so a 2-letter word on the way to a longer one
      // doesn't interrupt the player.
      final hit = runs.where((r) => r.word.length >= 3 && r.positions.contains(tile.cell)).toList();
      if (hit.isEmpty) continue;
      final names = nameChoicesFor(tile.id, taken: _book.names);
      final villager = Villager(
        id: tile.id,
        name: names.first,
        cell: tile.cell,
        movedInWord: hit.first.word,
        wish: _newWishFor(tile.cell, runs),
      );
      _setBook(_book.moveIn(villager));
      await _rewardsShowing; // one moment at a time
      if (!mounted) return;
      final name = await showMoveIn(context, villager: villager, word: hit.first.word, nameChoices: names);
      if (!mounted) return;
      _setBook(_book.rename(villager.id, name));
    }
    if (_book.isEmpty) return;

    // 2. Wishes that were waiting for today.
    final now = DateTime.now();
    final refreshed = _book.refreshWishes(now, (v) => _newWishFor(v.cell, runs));
    if (refreshed.villagers.where((v) => v.wish != null).length != _book.villagers.where((v) => v.wish != null).length) {
      _setBook(refreshed);
    }

    // 3. Wishes that came true.
    final result = _book.checkWishes(runs, now: now, ringAt: _islandMap.ringAtIndex);
    if (result.granted.isEmpty) return;
    _setBook(result.book);
    final portfolio = ref.read(portfolioProvider.notifier);
    for (final g in result.granted) {
      portfolio.addCurrency(g.coins); // paid first, as a moment requires
    }
    for (final g in result.granted) {
      await _rewardsShowing;
      if (!mounted) return;
      await showWishGranted(context, g);
    }
    for (final g in result.granted) {
      await _giveXp(g.xp);
    }
  }

  // XP outside a word (a wish), with the same level-up treats.
  Future<void> _giveXp(int xp) async {
    if (!mounted || xp <= 0) return;
    final levelBefore = levelInfoForXp(ref.read(portfolioProvider).totalXp).level;
    ref.read(portfolioProvider.notifier).addXp(xp);
    final levelAfter = levelInfoForXp(ref.read(portfolioProvider).totalXp).level;
    for (var lv = levelBefore + 1; lv <= levelAfter; lv++) {
      if (!_levelTreats.contains(lv)) await _doLevelTreat(lv);
    }
  }

  // VillagerHost: what the card and the Your villagers page ask of the screen.
  @override
  ValueListenable<VillagerBook> get villagerBook => _bookNotifier;

  @override
  WordLevel get wordLevel => ref.read(settingsProvider).wordLevel;

  @override
  IslandMap get islandMap => _islandMap;

  @override
  void renameVillager(String id, String name) => _setBook(_book.rename(id, name));

  @override
  void differentWish(String id) {
    final v = _book.byId(id);
    if (v == null || v.wish == null) return;
    _setBook(_book.swapWish(id, _newWishFor(v.cell, _wordRuns, previous: v.wish)));
  }

  @override
  void openVillagerCard(String id) => showVillagerCard(context, this, id);

  @override
  void findVillager(String id) {
    final v = _book.byId(id);
    if (v != null) _centerOn(_walkers.cellOf(id) ?? v.cell);
  }

  // Outlines through the fog for everything not found yet, and villagers not
  // met yet.
  List<GroundMark> _markers() => [
        for (final sp in _islandMap.specials)
          if (sp.kind == SpecialKind.villager ? !_book.isMet(sp.id) : !_foundSpecials.contains(sp.id))
            GroundMark(sp.cell, specialMarkerColor(sp.kind), seen: _fog.canSee(sp.cell)),
      ];

  List<VillagerSprite> _sprites() => [
        for (final v in _book.villagers) VillagerSprite(id: v.id, name: v.name, best: v.bestFriend),
      ];

  // Words view: a villager stands still on an empty square beside their word.
  Map<int, String> _standCells() {
    final board = ref.read(gridGameControllerProvider).boardCells;
    const bw = InfiniteEstateScreen.boardSize;
    final out = <int, String>{};
    for (final v in _book.villagers) {
      var spot = v.cell;
      if (board[v.cell] != null) {
        for (final d in const [1, bw, -1, -bw, bw + 1, bw - 1, -bw + 1, -bw - 1]) {
          final n = v.cell + d;
          if (n >= 0 && n < board.length && board[n] == null && !out.containsKey(n)) {
            spot = n;
            break;
          }
        }
      }
      out[spot] = v.id;
    }
    return out;
  }

  Widget? _wordsMarker(int index, Map<int, String> standing) {
    if (portTile(_portNow(), index) case final tile?) return tile;
    if (_starStart && index == _starCell && ref.read(gridGameControllerProvider).boardCells[index] == null) {
      return GoldStarMark(quiet: _starDone);
    }
    final id = standing[index];
    if (id != null) {
      final v = _book.byId(id)!;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openVillagerCard(id),
        child: Semantics(
          button: true,
          label: '${v.name}, villager. Tap for their wish.',
          child: FittedBox(child: Padding(padding: const EdgeInsets.all(4), child: VillagerFace(id: v.id, name: v.name, size: 44, happy: v.bestFriend))),
        ),
      );
    }
    final sp = _islandMap.specialAt(index);
    if (sp == null) return null;
    final unfound = sp.kind == SpecialKind.villager ? !_book.isMet(sp.id) : !_foundSpecials.contains(sp.id);
    if (!unfound) return null;
    final seen = _fog.canSee(index);
    final color = specialMarkerColor(sp.kind);
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.6,
          heightFactor: 0.6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(seen ? 0.3 : 0.15),
              border: Border.all(color: color.withOpacity(seen ? 0.95 : 0.5), width: 2.5),
            ),
          ),
        ),
      ),
    );
  }

  void _openVillagersPage() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VillagersPage(host: this)));
  }

  // Centers whichever view is showing on board cell [index].
  void _centerOn(int index) {
    if (_viewMode == _ViewMode.words) {
      _centerWordsOn(index, transformScale(_transformController.value));
      return;
    }
    _globe.currentState?.walkTo(index, math.max(kStreetZoom + 2, _globe.currentState!.zoom));
  }

  Future<void> _loadSavedVillage() async {
    final saved = await _saveController.load();
    if (!mounted) return;
    var needsSave = false;
    if (saved != null) {
      // Older saves (21-letter rack) are brought up to the current format
      // first; the extra letters go back to the pool, nothing is lost.
      final migrated = migrateVillageSave(saved,
          rackSize: InfiniteEstateScreen.rackSize, planetSlot: saved.planetSlot ?? 0);
      final controller = ref.read(gridGameControllerProvider.notifier);
      controller.restoreState(
        boardCells: migrated.boardCells,
        rackCells: migrated.rackCells,
        pool: migrated.pool,
        dealtLetters: migrated.dealtLetters,
        bag: migrated.bag,
      );
      // A migrated rack that held fewer than 10 letters is topped up.
      controller.fillEmptyBaseRackSlots();
      _lastCashedOutScore = migrated.lastCashedOutScore;
      _reachedLandmarks = migrated.reachedLandmarks;
      _discoveredWords = migrated.discoveredWords;
      // ── spec-15: restore explore state ──────────────────────────────────
      _mapSeed = migrated.mapSeed;
      _mapVersion = migrated.mapVersion;
      _everUsed = Set<int>.from(migrated.everUsed);
      _everWords = Set<String>.from(migrated.everWords);
      _foundSpecials = Set<String>.from(migrated.foundSpecials);
      _shrines = Set<ShrineKind>.from(migrated.shrines);
      _levelTreats = Set<int>.from(migrated.levelTreats);
      _bookNotifier.value = migrated.villagers;
      _tidiedLoose = migrated.tidiedLoose;
      _looseNote = migrated.looseNote;
      _keptRuns = migrated.keptRuns;
      // Build the island map for the restored seed.
      _slot = migrated.planetSlot ?? 0;
      _migratedFrom = migrated.migratedFrom;
      _islandMap = IslandMap.letterra(seed: _mapSeed, slot: _slot);
      // Restore fog; migration guarantees `cleared` is non-null for v3 saves.
      final clearedB64 = migrated.cleared;
      _fog = clearedB64 != null
          ? FogMap.fromBase64(clearedB64)
          : FogMap.empty();
      _starStart = migrated.starStart;
      _starDone = migrated.starDone;
      _bandsReached = migrated.bandsReached;
      _bandsQuiet = migrated.bandsReached == null;
      needsSave = saved.saveVersion != migrated.saveVersion || !identical(migrated.boardCells, saved.boardCells);
    }
    // spec-17: the first time an old village loads, any letters that aren't
    // in a real word go back to the rack. Nothing already earned is touched.
    if (saved != null && !_tidiedLoose) {
      final controller = ref.read(gridGameControllerProvider.notifier);
      // Every real word already standing is kept: its building stays even if
      // one of its letters also sits in a bad crossing (nothing breaks).
      final before = await controller.settledBoard(isValid: ref.read(wordCheckProvider));
      if (!mounted) return;
      _keptRuns = before.validRuns;
      final n = await controller.returnLooseToRack(
        isValid: ref.read(wordCheckProvider),
        keep: _protectedCells(),
      );
      if (!mounted) return;
      _looseNote += n;
      _tidiedLoose = true;
      needsSave = true;
    }
    if (saved == null) {
      // A brand-new village starts on the shore with a clear patch round it.
      _fog = FogMap.empty().clearAround([_harborIndex], radius: 6);
      _starStart = true;
    }
    // The shore and the meadow are where everyone starts: never celebrated.
    _bandsReached ??= {0, 1, ...regionsCleared(_fog)};
    _placeStar();
    setState(() => _restoring = false);
    // Write the migrated save straight away so migration only ever runs
    // once.
    if (needsSave) await _saveVillage();
    _showLooseNote();
    // Bring score/structures in sync with whatever board we ended up
    // with (restored or fresh).
    await _refreshStructures();
    if (_bandsQuiet) {
      _bandsQuiet = false;
      await _saveVillage();
    }
    await _refreshScore();
    await _takeGifts();
    if (widget.openVillagers && mounted) _openVillagersPage();
  }

  // "Mr. W put 3 letters back in your rack", once.
  void _showLooseNote() {
    if (!mounted || _looseNote <= 0) return;
    final n = _looseNote;
    _looseNote = 0;
    _saveVillage();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        n == 1
            ? "Mr. W put 1 letter in your bag: it wasn't in a word yet."
            : "Mr. W put $n letters in your bag: they weren't in a word yet.",
      ),
    ));
  }

  // spec-17: on leaving, loose letters go back to the rack. The village saves
  // after every change, so this writes the tidied board straight to disk
  // (using the last scan's loose cells; no dictionary needed, nothing waits).
  // The note is kept in the save for the next visit.
  void _saveTidiedForLeaving() {
    final stray = {..._strayCells}..removeAll(_protectedCells());
    if (_restoring || stray.isEmpty) return;
    final g = _lastGrid;
    if (g == null) return;
    final moved = returnLoose(g.boardCells, g.rackCells, g.bag, stray, rackSize: InfiniteEstateScreen.rackSize);
    if (moved.count == 0) return;
    _saveController.save(_snapshot(g, board: moved.board, rack: moved.rack, bag: moved.bag, note: _looseNote + moved.count));
  }

  // Squares the tidy-up never touches: found specials, the squares villagers
  // came from, and every word kept from before the rule.
  Set<int> _protectedCells() => {
        for (final sp in _islandMap.specials)
          if (sp.kind == SpecialKind.villager ? _book.isMet(sp.id) : _foundSpecials.contains(sp.id)) sp.cell,
        for (final r in _keptRuns) ...r.positions,
        for (final r in _wordRuns) ...r.positions,
      };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Going to the background may be for good: keep the tidied village on disk
    // (the screen itself keeps its letters if the player comes straight back).
    if (state == AppLifecycleState.paused) _saveTidiedForLeaving();
  }

  Future<void> _saveVillage() async {
    await _saveController.save(_snapshot(ref.read(gridGameControllerProvider)));
  }

  VillageSaveData _snapshot(GridGameState gridState,
      {List<String?>? board, List<String?>? rack, List<String>? bag, int? note}) {
    _lastGrid = gridState;
    return (VillageSaveData(
      boardCells: board ?? gridState.boardCells,
      rackCells: rack ?? gridState.rackCells,
      pool: gridState.pool,
      dealtLetters: gridState.dealtLetters,
      lastCashedOutScore: _lastCashedOutScore,
      reachedLandmarks: _reachedLandmarks,
      discoveredWords: _discoveredWords,
      // spec-15 explore state
      mapSeed: _mapSeed,
      mapVersion: _mapVersion,
      cleared: _fog.toBase64(),
      everUsed: Set<int>.unmodifiable(_everUsed),
      everWords: Set<String>.unmodifiable(_everWords),
      foundSpecials: Set<String>.unmodifiable(_foundSpecials),
      shrines: Set<ShrineKind>.unmodifiable(_shrines),
      levelTreats: Set<int>.unmodifiable(_levelTreats),
      villagers: _book,
      tidiedLoose: _tidiedLoose,
      looseNote: note ?? _looseNote,
      bag: bag ?? gridState.bag,
      keptRuns: _keptRuns,
      planetSlot: _slot,
      migratedFrom: _migratedFrom,
      starStart: _starStart,
      starDone: _starDone,
      bandsReached: _bandsReached,
    ));
  }

  void _togglePin(int rackIndex) {
    setState(() {
      if (_pinnedRackIndices.contains(rackIndex)) {
        _pinnedRackIndices.remove(rackIndex);
      } else {
        _pinnedRackIndices.add(rackIndex);
      }
    });
  }

  // Pins are keyed by rack slot, but the player pinned a *letter*. Keep
  // them attached to it: a pinned tile moved to another rack slot carries
  // its pin along, and one that leaves the rack (placed on the board)
  // loses it -- otherwise the auto-refilled letter that lands in its old
  // slot would show up pinned even though the player never pinned it.
  // One unavoidable blind spot: if a pinned letter is placed and the
  // refill happens to draw the identical letter into the same slot, the
  // two are indistinguishable and the pin stays.
  void _updatePinsAfterRackChange(GridGameState previous, GridGameState next) {
    // Gift stripes (spec-10) follow their letters the same way pins do.
    if (_giftRackIndices.isNotEmpty) {
      final gifts = _followLetters(_giftRackIndices, previous, next);
      if (gifts.length != _giftRackIndices.length || !gifts.containsAll(_giftRackIndices)) {
        setState(() => _giftRackIndices = gifts);
      }
    }
    if (_pinnedRackIndices.isEmpty) return;
    final updated = _followLetters(_pinnedRackIndices, previous, next);
    if (updated.length != _pinnedRackIndices.length || !updated.containsAll(_pinnedRackIndices)) {
      setState(() {
        _pinnedRackIndices
          ..clear()
          ..addAll(updated);
      });
    }
  }

  Set<int> _followLetters(Set<int> indices, GridGameState previous, GridGameState next) {
    final before = previous.rackCells;
    final after = next.rackCells;
    final boardChanged = previous.boardCells != next.boardCells;
    final updated = <int>{};
    for (final i in indices) {
      final letter = i < before.length ? before[i] : null;
      if (letter == null) continue;
      if (i < after.length && after[i] == letter) {
        updated.add(i);
        continue;
      }
      if (boardChanged) continue; // left the rack for the board
      // Rack-to-rack move: the letter appeared in a slot that was empty.
      for (int j = 0; j < after.length; j++) {
        final wasEmpty = j >= before.length || before[j] == null;
        if (j != i && wasEmpty && after[j] == letter) {
          updated.add(j);
          break;
        }
      }
    }
    return updated;
  }

  // Letter gifts from the family (spec-10): any waiting ones land in the
  // rack as bonus tiles, on top of the 10, once the village has loaded.
  Future<void> _takeGifts() async {
    final online = ref.read(familyOnlineProvider.notifier);
    await online.ready;
    // The family's notes arrive a moment after the family itself.
    for (int i = 0; i < 20 && mounted; i++) {
      if (ref.read(familyOnlineProvider).stage != OnlineStage.member) return;
      if (online.waitingGiftsForMe.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    final gifts = await online.takeGifts();
    if (!mounted || gifts.isEmpty) return;
    final controller = ref.read(gridGameControllerProvider.notifier);
    final added = <int>{};
    for (final g in gifts) {
      final slot = controller.addGiftLetter(g.letter!);
      if (slot >= 0) added.add(slot);
    }
    setState(() => _giftRackIndices = {..._giftRackIndices, ...added});
    await _saveVillage();
    if (!mounted) return;
    HapticFeedback.lightImpact();
    await showGiftsArrived(context, ref, gifts);
  }

  void _openJournal() {
    final rackCells = ref.read(gridGameControllerProvider).rackCells;
    final foundLandmarks = {
      for (final s in _islandMap.specials)
        if (s.kind == SpecialKind.landmark && _foundSpecials.contains(s.id)) s.landmark!,
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DiscoveryJournalView(
        loadDefinition: _loadDefinition,
        rackCells: rackCells,
        discoveredWords: _discoveredWords,
        foundLandmarks: foundLandmarks,
        villagersMet: _book.count,
        villagersTotal: _islandMap.villagers.length,
        onVillagers: () {
          Navigator.of(context).pop();
          _openVillagersPage();
        },
      ),
    );
  }

  // Re-derives which magic words are currently built (see BoardStructure's
  // doc comment: this is a rendering computation over the live board, not
  // a separately persisted structures list). Triggered after every board
  // change via ref.listen in build(); guarded against overlapping runs the
  // same way Theme Rush guards its own auto-check.
  //
  // "Discovered" (for the Discovery Journal) is a separate, permanent
  // record: once a magic word has been built at least once, it stays
  // marked discovered even if its letters are later moved away and the
  // structure itself disappears.
  Future<void> _refreshStructures() async {
    if (_computingStructures) return;
    _computingStructures = true;
    try {
      final controller = ref.read(gridGameControllerProvider.notifier);
      // A kept word stops being kept as soon as a letter of it moves.
      final stillKept = pruneKept(_keptRuns, ref.read(gridGameControllerProvider).boardCells);
      final keptChanged = stillKept.length != _keptRuns.length;
      if (keptChanged) _keptRuns = stillKept;
      final board = await controller.settledBoard(isValid: ref.read(wordCheckProvider), kept: _keptRuns);
      var runs = board.settledRuns;
      if (!mounted) return;
      // The first word must cover the gold star; after that it never matters.
      var offStar = const <int>{};
      if (_starActive) {
        if (runs.any((r) => r.positions.contains(_starCell))) {
          _starDone = true;
          ref.read(startCellProvider.notifier).state = null;
          await _saveVillage();
          if (!mounted) return;
        } else {
          offStar = {for (final r in runs) ...r.positions};
          runs = const [];
        }
      }
      if (keptChanged) await _saveVillage();
      final structures = computeStructures(runs);
      final newlyDiscovered = newDiscoveries(structures, _discoveredWords);
      setState(() {
        _structures = structures;
        _wordRuns = runs;
        _badRuns = board.badRuns;
        _looseCells = offStar.isEmpty ? board.looseCells : {...board.looseCells, ...offStar};
        _offStarCells = offStar;
        _strayCells = board.strayCells;
        _scene = null;
        if (newlyDiscovered.isNotEmpty) {
          _discoveredWords = {..._discoveredWords, ...newlyDiscovered};
        }
      });
      if (newlyDiscovered.isNotEmpty) {
        await _saveVillage();
        _celebrateNewBuildings(newlyDiscovered);
      }
      _syncWalkers();
      await _processExploreRewards(runs);
      await _processVillagers(runs);
      await _claimWordOfDay(runs);
    } finally {
      _computingStructures = false;
    }
  }

  // Word of the day (spec-05): the first time today that the word is
  // spelled anywhere in the village, +10 coins. A word that was already on
  // the board when the day started counts too -- rewards are only upside.
  Future<void> _claimWordOfDay(List<WordRun> runs) async {
    final List<WordOfDay> words;
    try {
      words = await ref.read(wordsOfTheDayProvider.future);
    } catch (_) {
      return; // No list, no reward; never an error for the player.
    }
    if (!mounted || words.isEmpty) return;
    final now = DateTime.now();
    final today = wordOfDayFor(now, words).word;
    if (!runs.any((run) => run.word.toUpperCase() == today)) return;
    final claims = ref.read(wordOfDayProvider.notifier);
    await claims.loaded;
    if (!mounted || !claims.claim(now)) return;
    ref.read(portfolioProvider.notifier).addCurrency(kWordOfDayCoins);
    await _rewardsShowing; // one moment at a time (a new building first)
    if (!mounted) return;
    await showRewardMoment(
      context,
      title: 'Word of the day!',
      word: today,
      message: 'You spelled it in your village.',
      coins: kWordOfDayCoins,
    );
  }

  // The new-building moment, while it's open; the word of the day waits
  // for it so two moments never stack.
  Future<void> _rewardsShowing = Future.value();

  Future<void> _refreshScore() async {
    if (_starActive) return;
    final controller = ref.read(gridGameControllerProvider.notifier);
    final result = await controller.checkWords();
    if (!mounted) return;
    // Only a fully-valid, connected board's word list is meaningful as a
    // score -- an in-progress invalid word shouldn't count yet.
    if (result.areValid && result.areConnected) {
      final newScore = scoreForWords(result.words);
      if (newScore != _score) {
        setState(() => _score = newScore);
        ref.read(modeStatsProvider.notifier).reportInfiniteEstateScore(newScore);
      }
    }
  }

  int get _freeSwapsLeft => freeSwapsLeft(used: _freeSwapsUsed, hasFarm: _hasStructure('FARM'));

  // spec-15: flash a small "+N XP" SnackBar after a word rewards XP.
  void _showXpFloat(int xp) {
    if (!mounted || xp <= 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('+$xp XP', style: WText.bodyBold.copyWith(color: WColors.white)),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF6A4FB6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // spec-15: show a level-up reward moment for reaching [level] and apply
  // any treat (larger rack for Shrine of Plenty is handled on shrine
  // activation; here we just celebrate).
  Future<void> _doLevelTreat(int level) async {
    _levelTreats = {..._levelTreats, level};
    await _saveVillage();
    if (!mounted) return;
    await _rewardsShowing;
    if (!mounted) return;
    _rewardsShowing = showRewardMoment(
      context,
      ribbon: 'Level up!',
      title: 'Level $level!',
      message: 'Your village is growing. Keep exploring!',
      coins: 0,
      buttonLabel: 'Onward!',
    );
  }

  // spec-18: the band under the centre of the view, with its word length.
  Widget _bandChip(Size viewport) {
    const bw = InfiniteEstateScreen.boardSize;
    final cell = centerCellOfFlatView(_transformController.value, viewport, InfiniteEstateScreen.cellSize,
        boardWidth: bw, boardHeight: bw);
    return _bandChipAt(cell.r * bw + cell.c);
  }

  Widget _bandChipAt(int index) {
    final text = bandChipText(
      _islandMap.bandAtIndex(index),
      ref.read(settingsProvider).wordLevel,
      bay: _islandMap.isSeaIndex(index) && _islandMap.bandAtIndex(index) != Band.deep,
    );
    return Container(
      key: const ValueKey('band-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: WColors.white.withOpacity(0.92),
        border: Border.all(color: WColors.ink, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: WText.bodyBold.copyWith(fontSize: 14, color: WColors.ink)),
    );
  }

  // spec-15: open the whole-island map page.
  void _openIslandMap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IslandMapPage(
          islandMap: _islandMap,
          fog: _fog,
          foundSpecialIds: {..._foundSpecials, for (final v in _book.villagers) v.id},
          onJumpTo: (boardIndex) {
            _centerWordsOn(boardIndex, transformScale(_transformController.value));
          },
        ),
      ),
    );
  }

  // +10 coins the first time each building is ever built, with the new
  // building moment (spec-12). Words already discovered (older saves
  // included) never pay again.
  void _celebrateNewBuildings(Set<String> words) {
    final coins = coinsForDiscoveries(words);
    ref.read(portfolioProvider.notifier).addCurrency(coins);
    if (!mounted) return;
    final defs = [for (final w in words) magicWordFor(w)!];
    final names = defs.map((d) => d.displayName).toList();
    final title = names.length == 1
        ? 'You built a ${names.first}!'
        : 'You built a ${names.sublist(0, names.length - 1).join(', a ')} and a ${names.last}!';
    final what = names.length == 1 ? defs.first.description : null;
    _rewardsShowing = _newBuildingMoment(
      defs.first.word,
      () => showRewardMoment(
        context,
        ribbon: 'New building!',
        title: title,
        message: [
          if (what != null) what,
          'Tap ${names.length == 1 ? 'it' : 'them'} on the planet to see more.',
        ].join('\n'),
        coins: coins,
        buttonLabel: 'Hooray!',
        sound: Sfx.building,
        lookThrough: true,
      ),
    );
  }

  // The planet's close-up, the building dropping into place beside its word,
  // then [moment] over it, and back to Words just as it was. The coins are
  // already paid, however this ends.
  Future<void> _newBuildingMoment(String word, Future<void> Function() moment) async {
    final built = _structures.where((b) => b.def.word == word).toList();
    if (built.isEmpty) return moment();
    final cells = built.last.ordered;
    final data = _livePlanet();
    final home = homeOf(data.villages.first, cells)?.cell ?? built.last.middle;
    final reduce = ref.read(settingsProvider).reduceMotion;
    final fromWords = _viewMode == _ViewMode.words;
    setState(() {
      _planetBusy = true;
      if (fromWords) _showPlanetAt(home, reduce ? kCloseUpMaxZoom : kStreetZoom);
      _drop = reduce ? null : (cells: cells, t: 0);
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _globe.currentState?.walkTo(home, kCloseUpMaxZoom, milliseconds: 900);
    if (!mounted) return;
    if (!reduce) {
      void move() => setState(() => _drop = (cells: cells, t: Curves.bounceOut.transform(_dropAnim.value)));
      _dropAnim.addListener(move);
      await _dropAnim.forward(from: 0).orCancel.catchError((_) {});
      _dropAnim.removeListener(move);
      if (!mounted) return;
    }
    setState(() => _drop = null);
    await moment();
    if (!mounted) return;
    setState(() {
      _planetBusy = false;
      if (fromWords) _viewMode = _ViewMode.words;
    });
  }

  // Swap letters: pinned letters stay, the rest are traded for balanced
  // draws. The Farm's free swap is used first if available; otherwise it
  // costs swapCost coins, spent only once the swap actually happened.
  void _swapRack() {
    final free = _freeSwapsLeft > 0;
    if (!free && ref.read(portfolioProvider).currency < InfiniteEstateScreen.swapCost) return;
    final swapped = ref.read(gridGameControllerProvider.notifier).swapRack(keepIndices: _pinnedRackIndices);
    if (!swapped) return;
    if (free) {
      setState(() => _freeSwapsUsed++);
    } else {
      ref.read(portfolioProvider.notifier).spendCurrency(InfiniteEstateScreen.swapCost);
    }
  }

  // True when no base rack letter is left unpinned, i.e. Swap would have
  // nothing to trade.
  bool _allBaseSlotsPinned(List<String?> rack) {
    for (int i = 0; i < InfiniteEstateScreen.rackSize && i < rack.length; i++) {
      if (rack[i] != null && !_pinnedRackIndices.contains(i)) return false;
    }
    return true;
  }

  // Until there's a building: which one you are nearest to.
  Widget _firstBuildingHelper(int cell) {
    final grid = ref.read(gridGameControllerProvider);
    final closest = closestBuilding(grid.rackCells, grid.boardCells);
    return FirstBuildingHelper(
      def: closest.def,
      have: closest.have,
      haveEach: closest.haveEach,
      spritePath: _spriteMeta[closest.def.word]?.spritePath,
      onGoToWords: () => _openWordsAt(cell),
    );
  }

  // The same in one line, for Words.
  String _firstBuildingText() {
    final grid = ref.watch(gridGameControllerProvider);
    final closest = closestBuilding(grid.rackCells, grid.boardCells);
    return 'Build ${closest.def.word}: ${closest.have} of ${closest.def.word.length} letters';
  }

  void _drawFromWell() {
    if (_wellUsedThisVisit) return;
    // Only spend the once-per-visit draw if a letter actually arrived
    // (it can't when the pool is empty).
    final gotLetter = ref.read(gridGameControllerProvider.notifier).drawBonusLetter();
    if (gotLetter) setState(() => _wellUsedThisVisit = true);
  }

  // Runs once, the first time the board area's real size is known, to
  // start the player looking at the village's origin instead of the
  // board's empty top-left corner (InteractiveViewer's default).
  void _centerViewIfNeeded(Size viewportSize) {
    if (_viewCentered) return;
    _viewCentered = true;
    // The middle of all the letters (the board center if there are none).
    final center = _villageScene().lettersCenter(emptyCell: _harborIndex);
    final centerIndex = widget.focusCell ?? center.r * InfiniteEstateScreen.boardSize + center.c;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transformController.value = computeCenterTransform(
        viewportSize: viewportSize,
        boardIndex: centerIndex,
        boardWidth: InfiniteEstateScreen.boardSize,
        cellSize: InfiniteEstateScreen.cellSize,
        scale: 1.0,
      );
    });
  }

  // Words' Planet button: down in your streets, at the same spot.
  void _openPlanet() {
    final viewport = _boardViewportSize;
    var cell = _harborIndex;
    if (viewport != null) {
      const bw = InfiniteEstateScreen.boardSize;
      final c = centerCellOfFlatView(_transformController.value, viewport, InfiniteEstateScreen.cellSize,
          boardWidth: bw, boardHeight: bw);
      cell = c.r * bw + c.c;
    }
    setState(() => _showPlanetAt(cell, kCloseUpMaxZoom));
  }

  void _showPlanetAt(int cell, double zoom) {
    _globe = GlobalKey<GlobeViewState>();
    _planetCell = cell;
    _planetZoom = zoom;
    _viewMode = _ViewMode.planet;
  }

  // Build: Words at the square in the middle of the planet's view.
  void _openWordsAt(int cell) => _centerWordsOn(cell, transformScale(_transformController.value));

  // Switches to Words view centered on board cell [index].
  void _centerWordsOn(int index, double scale) {
    final fallback = _boardViewportSize;
    _viewCentered = true;
    setState(() => _viewMode = _ViewMode.words);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewport = _boardViewportSize ?? fallback;
      if (!mounted || viewport == null) return;
      _transformController.value = computeCenterTransform(
        viewportSize: viewport,
        boardIndex: index,
        boardWidth: InfiniteEstateScreen.boardSize,
        cellSize: InfiniteEstateScreen.cellSize,
        scale: scale,
      );
    });
  }

  void _showInWords(List<int> positions) {
    _openWordsAt(positions[(positions.length - 1) ~/ 2]);
  }

  Future<String?> _loadDefinition(String word) => ref.read(definitionServiceProvider).getDefinition(word);

  // ── The planet (spec-22) ──────────────────────────────────────────────────

  // The planet with your village as it is right now. The same object until
  // something on it changes, so nothing is worked out or painted again.
  PlanetData _livePlanet() {
    final board = ref.read(gridGameControllerProvider).boardCells;
    final others = widget.planet?.value?.others ?? const <PlanetVillage>[];
    final key = [board, _structures, _looseCells, _fog, _foundSpecials, _book, others];
    var same = _planetData != null && key.length == _planetKey.length;
    for (var i = 0; same && i < key.length; i++) {
      same = identical(key[i], _planetKey[i]);
    }
    if (same) return _planetData!;
    _planetKey = key;
    _planetMarks = _markers();
    final letters = {
      for (var i = 0; i < board.length; i++)
        if (board[i] != null) i: board[i]!,
    };
    return _planetData = PlanetData.of(
      PlanetVillage(
        player: ref.read(playersProvider).current,
        slot: _slot,
        letters: letters,
        runs: [for (final b in _structures) (word: b.def.word, cells: b.ordered)],
        fog: _fog,
        loose: _looseCells,
      ),
      others,
      thingsToFind(
        map: _islandMap,
        count: _shrines.contains(ShrineKind.sight) ? 3 : 1,
        unfound: [for (final m in _planetMarks) m.cell],
        letters: letters.keys,
        level: ref.read(settingsProvider).wordLevel,
      ),
    );
  }

  void _onStreetTap(Offset at, GlobeProjection proj, PlanetData data) {
    final hit = streetHit(at, proj, data.villages.first, villagers: {
      for (final v in _book.villagers) v.id: _walkers.positionOf(v.id),
    });
    switch (hit) {
      case StreetVillager(:final id):
        openVillagerCard(id);
      case StreetBuilding(:final run):
        if (run < _structures.length) _openBuildingCard(_structures[run]);
      case StreetLetter(:final cell):
        _openWordCard(cell);
      case null:
        break;
    }
  }

  // Your own village: down to the streets, and stay. Another player's: fly
  // down and look.
  Future<void> _dive(PlanetData data, int slot) async {
    if (_planetBusy) return;
    setState(() => _planetBusy = true);
    final reduce = ref.read(settingsProvider).reduceMotion;
    if (!reduce) ref.read(soundProvider).play(Sfx.whoosh);
    await _globe.currentState?.diveTo(slot);
    if (!mounted) return;
    final player = data.players[slot];
    if (slot != data.mySlot && player != null) {
      await Navigator.of(context).push(PageRouteBuilder<void>(
        transitionDuration: Duration(milliseconds: reduce ? 0 : 280),
        reverseTransitionDuration: Duration(milliseconds: reduce ? 0 : 220),
        pageBuilder: (_, __, ___) => VisitVillageScreen(player: player),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
      if (!mounted) return;
      _globe.currentState?.showWhole(slot);
    }
    setState(() => _planetBusy = false);
  }

  // Something to find: fly there, then Words at that square.
  Future<void> _showFind(PlanetData data, int cell) async {
    if (_planetBusy) return;
    setState(() => _planetBusy = true);
    if (!ref.read(settingsProvider).reduceMotion) {
      ref.read(soundProvider).play(Sfx.whoosh);
      await _globe.currentState?.diveTo(data.mySlot, cell: cell);
      if (!mounted) return;
    }
    _planetBusy = false;
    _openWordsAt(cell);
  }

  Widget _planetPage() {
    final reduce = ref.watch(settingsProvider.select((st) => st.reduceMotion));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: kGlobeSky,
        body: AnimatedBuilder(
          animation: widget.planet ?? _bookNotifier,
          builder: (context, _) {
            final data = _restoring ? widget.planet?.value : _livePlanet();
            if (data == null) return const Center(child: CircularProgressIndicator());
            final text = MediaQuery.textScalerOf(context).scale(1);
            final low = MediaQuery.paddingOf(context).bottom;
            final helper = !_restoring && _structures.isEmpty;
            return IgnorePointer(
              ignoring: _planetBusy,
              child: GlobeView(
                key: _globe,
                villages: data.villages,
                takenSlots: data.takenSlots,
                focusSlot: data.mySlot,
                isHushed: data.isHushed,
                reduceMotion: reduce,
                alwaysPan: true,
                closeUp: true,
                initialCell: _planetCell,
                initialZoom: _planetZoom,
                showTags: !_planetBusy || _drop == null,
                marks: _restoring ? const [] : _planetMarks,
                highlight: _highlight,
                starCell: _starStart ? _starCell : null,
                starQuiet: _starDone,
                drop: _drop,
                showZoomButtons: !_planetBusy,
                zoomButtonsBottomFor: (zoom) =>
                    low +
                    (zoom >= kBuildZoom
                        ? (helper ? 110 + 110 * text : 84)
                        : data.find == null
                            ? 84
                            : 120 + 74 * text),
                glowCells: _planetBusy ? const [] : [for (final f in data.finds) f.cell],
                onGlowTap: (cell) => _showFind(data, cell),
                onVillageTap: (slot) => _dive(data, slot),
                onStreetTap: _restoring ? (_, __) {} : (at, proj) => _onStreetTap(at, proj, data),
                overlay: (proj, cell) => [
                  if (!_restoring && proj.zoom >= kStreetZoom)
                    Positioned.fill(child: StreetVillagers(proj: proj, walkers: _walkers, sprites: _sprites())),
                  if (!_planetBusy) _planetControls(data, proj.zoom, cell, helper),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _planetControls(PlanetData data, double zoom, int cell, bool helper) {
    final near = zoom >= kBuildZoom;
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(WSize.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                ChunkyIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: near && !_restoring
                      ? Center(child: FittedBox(fit: BoxFit.scaleDown, child: _bandChipAt(cell)))
                      : Text(
                          kPlanetName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: WText.heading.copyWith(fontSize: 28, color: WColors.ink),
                        ),
                ),
                const SizedBox(width: WSize.tapTarget),
              ]),
              const Spacer(),
              if (!near)
                PlanetBottom(
                  find: data.find,
                  onFindMe: () => _globe.currentState?.flyHome(data.mySlot),
                  onTurn: () => _globe.currentState?.turnTo(data.find!.cell),
                  onShow: () => _showFind(data, data.find!.cell),
                )
              else if (helper)
                _firstBuildingHelper(cell)
              else if (!_restoring)
                ChunkyButton(
                  key: const ValueKey('planet-build'),
                  label: 'Build',
                  icon: Icons.grid_view_rounded,
                  kind: ChunkyKind.mode,
                  modeColor: WColors.sun,
                  size: ChunkySize.big,
                  expand: true,
                  onPressed: () => _openWordsAt(cell),
                ),
            ],
          ),
        ),
      ),
    );
  }

  BuildingAbility? _abilityFor(MagicWordDef def, BuildContext sheetContext) {
    switch (def.word) {
      case 'WELL':
        return BuildingAbility(
          _wellUsedThisVisit ? 'Well used' : 'Draw a free letter',
          _wellUsedThisVisit
              ? null
              : () {
                  _drawFromWell();
                  Navigator.of(sheetContext).pop();
                },
        );
      case 'BRIDGE':
        return BuildingAbility(
          'Jump to a place',
          _foundPlaces().isEmpty
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  _openBridgeJumpMenu();
                },
        );
      default:
        return null;
    }
  }

  Future<void> _openBuildingCard(BoardStructure structure) async {
    setState(() => _highlight = structure.positions);
    await showVillageSheet<void>(
      context,
      Builder(
        builder: (sheetContext) => BuildingCard(
          def: structure.def,
          cardImagePath: _spriteMeta[structure.def.word]?.cardPath,
          loadDefinition: _loadDefinition,
          ability: _abilityFor(structure.def, sheetContext),
          onShowInWords: () {
            Navigator.of(sheetContext).pop();
            _showInWords(structure.ordered);
          },
        ),
      ),
    );
    if (mounted) setState(() => _highlight = const {});
  }

  Future<void> _openWordCard(int index) async {
    final runs = _wordRuns.where((r) => r.positions.contains(index)).toList()
      ..sort((a, b) => (a.across ? 0 : 1).compareTo(b.across ? 0 : 1));
    if (runs.isEmpty || _looseCells.contains(index)) {
      final bad = _badRuns.where((r) => r.positions.contains(index)).toList();
      await showVillageSheet<void>(context, NotAWordCard(
            run: bad.isEmpty ? null : bad.first.word,
            offStar: _offStarCells.contains(index),
          ));
      return;
    }
    setState(() => _highlight = runs.first.positions.toSet());
    await showVillageSheet<void>(
      context,
      Builder(
        builder: (sheetContext) => WordCard(
          runs: runs,
          loadDefinition: _loadDefinition,
          onWordChanged: (run) => setState(() => _highlight = run.positions.toSet()),
          onShowInWords: (run) {
            Navigator.of(sheetContext).pop();
            _showInWords(run.positions);
          },
        ),
      ),
    );
    if (mounted) setState(() => _highlight = const {});
  }

  // Landmarks and shrines found so far, in the order the map lists them.
  List<SpecialTile> _foundPlaces() => [
        for (final sp in _islandMap.specials)
          if ((sp.kind == SpecialKind.landmark || sp.kind == SpecialKind.shrine) && _foundSpecials.contains(sp.id)) sp,
      ];

  // Bridge: jump to the landmarks and shrines you have found (spec-16).
  void _openBridgeJumpMenu() {
    final places = _foundPlaces();
    showVillageSheet<void>(
      context,
      Builder(
        builder: (sheetContext) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(header: true, child: const Text('Bridge: jump to...', style: WText.heading)),
            const SizedBox(height: 4),
            const Text('Your Bridge takes you straight to places you\'ve found on the island.', style: WText.label),
            const SizedBox(height: WSize.gap3),
            if (places.isEmpty)
              const Text('Nothing found yet. Landmarks and shrines show up here once you reach them.', style: WText.body),
            for (final sp in places)
              Padding(
                padding: const EdgeInsets.only(bottom: WSize.gap2),
                child: ChunkyButton(
                  label: sp.kind == SpecialKind.landmark ? sp.landmark!.displayName : sp.shrine!.displayName,
                  icon: sp.kind == SpecialKind.landmark ? Icons.flag : Icons.auto_awesome,
                  kind: ChunkyKind.mode,
                  modeColor: sp.kind == SpecialKind.landmark ? WColors.sun : WColors.lilac,
                  expand: true,
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _centerOn(sp.cell);
                  },
                ),
              ),
            ChunkyButton(
              label: 'Close',
              kind: ChunkyKind.secondary,
              expand: true,
              onPressed: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  bool _cashingOut = false;

  Future<void> _endSession() async {
    if (_cashingOut) return;
    // Only newly-grown score since the last cash-out is ever paid out, so
    // reopening an unchanged village and ending again awards nothing.
    final earned = (_score - _lastCashedOutScore).clamp(0, 1 << 30);

    var confirmed = false;
    await showWordlerDialog<void>(
      context,
      title: 'Wrap up for now?',
      bodyText: earned > 0
          ? 'Cash out $earned points of growth since your last visit? Your village stays exactly as built.'
          : "You haven't grown the village since your last visit, so there's nothing new to cash out -- but your village is saved either way.",
      actions: [
        WordlerDialogAction('Keep Playing', () {}),
        WordlerDialogAction('Leave Village', () => confirmed = true, kind: ChunkyKind.secondary),
      ],
    );
    if (!confirmed) return;
    _cashingOut = true;

    final isNewHighScore = ref.read(modeStatsProvider.notifier).reportInfiniteEstateScore(_score);
    if (earned > 0) {
      final portfolioController = ref.read(portfolioProvider.notifier);
      // spec-15: XP is now earned per-word on placement, not at cash-out.
      portfolioController.addCurrency(earned ~/ 20);
      _lastCashedOutScore = _score;
      await _saveVillage();
    }

    if (!mounted) return;
    showWordlerDialog<void>(
      context,
      title: 'See You Next Time!',
      barrierDismissible: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Village score: $_score'),
          if (earned > 0) Text('+${earned ~/ 20} coins, +${earned ~/ 10} XP this visit'),
          if (isNewHighScore) ...[
            const SizedBox(height: 8),
            Text('New high score!', style: WText.bodyBold.copyWith(color: WColors.grass)),
          ],
        ],
      ),
      actions: [
        WordlerDialogAction('Done', () => Navigator.of(context).pop()),
      ],
    );
    _cashingOut = false;
  }

  @override
  Widget build(BuildContext context) {
    // Recompute which magic words are currently built, and re-save, any
    // time the board/rack/pool changes -- keeps the planet in sync and
    // keeps the persisted village current without the player needing to
    // press anything or remember to save before leaving.
    ref.listen(gridGameControllerProvider, (previous, next) {
      _lastGrid = next;
      if (previous?.boardCells != next.boardCells) {
        _refreshStructures();
      }
      if (previous != null && previous.rackCells != next.rackCells) {
        _updatePinsAfterRackChange(previous, next);
      }
      if (!_restoring) _saveVillage();
    });

    if (_viewMode == _ViewMode.planet) return _planetPage();

    if (_restoring) {
      return const WordlerScaffold(
        title: 'Infinite Estate',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final stripes = buildingStripes(_structures);
    final standing = _standCells();

    // Leaving never needs a confirm: the village saves after every change.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: WColors.paper,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(WSize.gamePadding, WSize.gamePadding, WSize.gamePadding, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChunkyIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Leave village (it saves automatically)',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: WSize.gap2),
                    Expanded(
                      child: ChunkyButton(
                        key: const ValueKey('words-planet'),
                        label: 'Planet',
                        icon: Icons.public,
                        kind: ChunkyKind.mode,
                        modeColor: WColors.sun,
                        size: ChunkySize.small,
                        expand: true,
                        onPressed: _openPlanet,
                      ),
                    ),
                    const SizedBox(width: WSize.gap2),
                    ChunkyIconButton(
                      icon: Icons.map,
                      tooltip: 'Island map',
                      onPressed: _openIslandMap,
                    ),
                    const SizedBox(width: WSize.gap2),
                    ChunkyButton(label: 'End', kind: ChunkyKind.danger, size: ChunkySize.small, onPressed: _endSession),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: WSize.gamePadding, vertical: WSize.gap2),
                child: _VillageActionBar(
                  score: _score,
                  onScoreTap: _refreshScore,
                  totalXp: ref.watch(portfolioProvider.select((p) => p.totalXp)),
                  discoveredCount: _discoveredWords.length,
                  totalMagicWords: kMagicWords.length,
                  onJournal: _openJournal,
                  villagersMet: _book.count,
                  villagersTotal: _islandMap.villagers.length,
                  onVillagers: _openVillagersPage,
                  showWell: _hasStructure('WELL'),
                  wellUsed: _wellUsedThisVisit,
                  onWell: _drawFromWell,
                  showBridge: _hasStructure('BRIDGE') && _foundPlaces().isNotEmpty,
                  onBridge: _openBridgeJumpMenu,
                  buildingCount: _structures.length,
                  firstBuilding: _structures.isEmpty ? _firstBuildingText() : null,
                  // Explains the stripes until there are a few buildings.
                  // Worked out from the live structures, not saved.
                  showStripeHint: _structures.length == 1,
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: WColors.grassField,
                    border: Border.symmetric(horizontal: BorderSide(color: WColors.ink, width: WSize.outline)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Recorded (not setState'd -- this must never trigger a
                      // rebuild mid-layout) purely so the Bridge jump ability
                      // knows the current viewport size when it's used later.
                      _boardViewportSize = constraints.biggest;
                      _centerViewIfNeeded(constraints.biggest);
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: GridBoardView(
                              key: const ValueKey('words'),
                              theme: _estateTheme,
                              // Same zoom feel as every other mode's board; the
                              // generous pan boundary past the lazily-built
                              // board's own huge extent keeps panning to an edge
                              // from ever feeling like hitting a wall.
                              minScale: 0.2,
                              maxScale: 2.5,
                              boundaryMargin: const EdgeInsets.all(400),
                              transformController: _transformController,
                              cellSize: InfiniteEstateScreen.cellSize,
                              stripes: stripes,
                              // spec-15: fog overlay and drop gate.
                              cellOverlay: _fogOverlay,
                              canDropAt: (i) => _fog.canSee(i) && !_islandMap.isSeaIndex(i),
                              cellMarker: (i) => _wordsMarker(i, standing),
                              looseCells: _looseCells,
                              onLooseTap: _openWordCard,
                            ),
                          ),
                          if (_starActive)
                            const Positioned(top: 8, left: 12, right: 12, child: IgnorePointer(child: _StarHint())),
                          // spec-18: which band is under the middle of the view.
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: IgnorePointer(
                              child: ValueListenableBuilder<Matrix4>(
                                valueListenable: _transformController,
                                builder: (context, _, __) => _bandChip(constraints.biggest),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(WSize.gamePadding, WSize.gap3, WSize.gamePadding, WSize.gamePadding),
                child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The rack sized to its content (square tiles, every row
                          // visible; a bonus letter adds a row), with Swap in a
                          // column beside it, so the board gets the height.
                          LayoutBuilder(builder: (context, constraints) {
                            const swapWidth = 72.0;
                            const gap = 8.0;
                            const frame = WSize.outline * 2 + 4 * 2;
                            final rackLength = ref.watch(gridGameControllerProvider.select((s) => s.rackCells.length));
                            final cell = (constraints.maxWidth - swapWidth - gap - frame) / 5;
                            final rackHeight = (rackLength / 5).ceil() * cell + frame;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: WColors.soil,
                                      border: Border.all(color: WColors.ink, width: WSize.outline),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        GridRackView(
                                          theme: _estateTheme,
                                          crossAxisCount: 5,
                                          childAspectRatio: 1.0,
                                          bordered: false,
                                          cellPadding: 2,
                                          pinnedIndices: _pinnedRackIndices,
                                          onTogglePin: _togglePin,
                                          stripes: {for (final i in _giftRackIndices) i: WColors.sun},
                                        ),
                                        const LetterBagChip(),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: gap),
                                SizedBox(
                                  width: swapWidth,
                                  height: rackHeight,
                                  child: _SwapColumn(
                                    allPinned: _allBaseSlotsPinned(
                                        ref.watch(gridGameControllerProvider.select((s) => s.rackCells))),
                                    freeLeft: _freeSwapsLeft,
                                    canAfford: ref.watch(portfolioProvider.select((p) => p.currency)) >=
                                        InfiniteEstateScreen.swapCost,
                                    onSwap: _swapRack,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a brand-new village says until its first word is down.
class _StarHint extends StatelessWidget {
  const _StarHint();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: WColors.card,
            border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Your first word must cover the gold star',
            textAlign: TextAlign.center,
            style: WText.bodyBold.copyWith(fontSize: 16, color: WColors.ink),
          ),
        ),
      );
}

// The row under the top bar: village score plus every structure ability
// and the Journal, as pill chips. A Wrap (not a Row) so a narrow phone or
// a large system text size flows onto a second line instead of
// overflowing or shrinking the text.
class _VillageActionBar extends StatelessWidget {
  const _VillageActionBar({
    required this.score,
    required this.onScoreTap,
    required this.totalXp,
    required this.discoveredCount,
    required this.totalMagicWords,
    required this.onJournal,
    required this.villagersMet,
    required this.villagersTotal,
    required this.onVillagers,
    required this.showWell,
    required this.wellUsed,
    required this.onWell,
    required this.showBridge,
    required this.onBridge,
    this.buildingCount,
    this.firstBuilding,
    this.showStripeHint = false,
  });

  final int score;
  final VoidCallback onScoreTap;
  // spec-15: total XP for the XP chip (replaces the score chip).
  final int totalXp;
  final int discoveredCount;
  final int totalMagicWords;
  final VoidCallback onJournal;
  // spec-16: shown once someone has moved in.
  final int villagersMet;
  final int villagersTotal;
  final VoidCallback onVillagers;
  final bool showWell;
  final bool wellUsed;
  final VoidCallback onWell;
  final bool showBridge;
  final VoidCallback onBridge;
  final int? buildingCount;
  // Until there's a building: the one you are nearest to.
  final String? firstBuilding;
  final bool showStripeHint;

  @override
  Widget build(BuildContext context) {
    final lvInfo = levelInfoForXp(totalXp);
    return Wrap(
      spacing: WSize.gap2,
      runSpacing: WSize.gap1,
      children: [
        PillChip(
          icon: Icons.star,
          value: 'Lv ${lvInfo.level}',
          label: '${lvInfo.xpIntoLevel}/${lvInfo.xpForNextLevel}',
          badgeColor: WColors.sun,
          tooltip: 'Level ${lvInfo.level}: ${lvInfo.xpIntoLevel} of ${lvInfo.xpForNextLevel} XP',
        ),
        // The Well's and Bridge's own chips take its room (two rows at most).
        if (buildingCount != null && !(showWell && showBridge))
          PillChip(
            icon: Icons.house,
            value: '$buildingCount',
            tooltip: buildingCount == 1 ? '1 building' : '$buildingCount buildings',
            badgeColor: WColors.leaf,
          ),
        PillChip(
          icon: Icons.menu_book,
          value: '$discoveredCount/$totalMagicWords',
          badgeColor: WColors.sun,
          tooltip: 'Journal',
          onTap: onJournal,
        ),
        if (villagersMet > 0)
          PillChip(
            icon: Icons.people,
            value: '$villagersMet/$villagersTotal',
            badgeColor: const Color(0xFFF2A0B8),
            tooltip: 'Your villagers',
            onTap: onVillagers,
          ),
        if (firstBuilding != null) PillChip(icon: Icons.construction, value: firstBuilding!, badgeColor: WColors.leaf),
        if (showStripeHint)
          const PillChip(icon: Icons.horizontal_rule, value: 'Stripe = building', badgeColor: WColors.leaf),
        if (showWell)
          PillChip(
            icon: Icons.water_drop,
            value: wellUsed ? 'Well used' : 'Free letter',
            badgeColor: WColors.sky,
            color: WColors.skyTint,
            enabled: !wellUsed,
            onTap: onWell,
          ),
        if (showBridge)
          PillChip(
            icon: Icons.alt_route,
            value: 'Jump',
            badgeColor: WColors.wood,
            onTap: onBridge,
          ),
      ],
    );
  }
}

// "Swap" in a column beside the rack: icon, label, and what it costs.
class _SwapColumn extends StatelessWidget {
  const _SwapColumn({
    required this.allPinned,
    required this.freeLeft,
    required this.canAfford,
    required this.onSwap,
  });

  final bool allPinned;
  final int freeLeft;
  final bool canAfford;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    const cost = InfiniteEstateScreen.swapCost;
    final free = freeLeft > 0;
    final enabled = !allPinned && (free || canAfford);
    final String chip = allPinned
        ? 'All letters pinned'
        : (free ? (freeLeft > 1 ? 'Free x2' : 'Free') : (canAfford ? '$cost coins' : 'Need $cost coins'));
    final chipColor = !enabled ? WColors.boardCell : (free ? WColors.leaf : WColors.sun);
    final ink = enabled ? WColors.ink : WColors.muted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Swap letters, $chip',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onSwap : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: WSize.lip),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: enabled ? WColors.card : WColors.boardCell,
            border: Border.all(color: ink, width: WSize.outline),
            borderRadius: BorderRadius.circular(WSize.radiusButton),
            boxShadow: enabled ? wLip(WSize.lip) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(allPinned ? Icons.push_pin : Icons.swap_horiz, color: ink, size: 26),
              Text('Swap', style: WText.buttonSmall.copyWith(color: ink)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: chipColor,
                  border: Border.all(color: ink, width: WSize.outlineSmall),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(chip, textAlign: TextAlign.center, style: WText.label.copyWith(color: ink, height: 1.1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
