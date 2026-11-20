import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../daily/word_of_the_day.dart';
import '../daily/word_of_the_day_controller.dart';
import '../dictionary/definition_service.dart';
import '../explore/explore_rules.dart';
import '../explore/fog.dart';
import '../explore/island_map.dart';
import '../portfolio/level_info.dart';
import '../settings/settings_controller.dart' show settingsProvider;
import 'island_map_screen.dart';
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_game_state.dart';
import '../game/grid_providers.dart';
import '../game/word_landing.dart' show wordCheckProvider;
import '../game/word_runs.dart';
import '../online/family_online_controller.dart';
import 'helping_screens.dart' show showGiftsArrived;
import '../portfolio/portfolio_controller.dart';
import '../stats/mode_stats_controller.dart';
import '../village/bridge_transform.dart';
import '../village/discovery_journal_view.dart';
import '../village/iso_math.dart';
import '../village/iso_village_view.dart';
import '../village/landmark.dart';
import '../village/magic_word.dart';
import '../village/structures.dart';
import '../village/village_art.dart';
import '../village/village_cards.dart';
import '../village/village_rewards.dart';
import '../village/village_save.dart';
import '../village/village_save_migration.dart';

import '../ui/chunky_button.dart';
import '../sound/sound_service.dart';
import '../ui/pill_chip.dart';
import '../ui/reward_moment.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import '../ui/wordler_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ViewMode { words, village }

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
  const InfiniteEstateScreen({super.key});

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
      ],
      child: const _InfiniteEstateBody(),
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
  const _InfiniteEstateBody();

  @override
  ConsumerState<_InfiniteEstateBody> createState() => _InfiniteEstateBodyState();
}

class _InfiniteEstateBodyState extends ConsumerState<_InfiniteEstateBody> {
  int _score = 0;
  // Score value already paid out as currency/XP -- End Session only
  // rewards growth past this, so re-visiting an unchanged village and
  // ending again doesn't re-pay the same structures.
  int _lastCashedOutScore = 0;
  _ViewMode _viewMode = _ViewMode.words;
  List<BoardStructure> _structures = [];
  bool _computingStructures = false;

  final _saveController = VillageSaveController();
  bool _restoring = true;

  // ── spec-15 explore state ────────────────────────────────────────────────
  late IslandMap _islandMap;
  FogMap _fog = FogMap.empty(); // replaced once the save loads
  int _mapSeed = VillageSaveData.kDefaultMapSeed;
  int _mapVersion = VillageSaveData.kDefaultMapVersion;
  Set<int> _everUsed = {};
  Set<String> _everWords = {};
  Set<String> _foundSpecials = {};
  Set<ShrineKind> _shrines = {};
  Set<int> _levelTreats = {};
  // Bridge ability: ordered list of reached old landmarks, kept for the
  // jump menu. Only index matters; never re-computed from scratch.
  late final List<int> _landmarkOrder;
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
  // spec-15: hints used this visit (1 normally, 3 with Shrine of Sight).
  int _hintsUsedThisVisit = 0;

  // Bridge structure ability: drives GridBoardView's InteractiveViewer to
  // jump/pan to a reached landmark. _boardViewportSize is captured by the
  // LayoutBuilder wrapping the board area and used to compute the jump
  // transform (see bridge_transform.dart) -- it's only known once that
  // area has actually been laid out, hence nullable.
  final _transformController = TransformationController();
  // Village view has its own camera (its content is the angled map).
  final _villageTransform = TransformationController();
  bool _villageCentered = false;
  static const _isoGrid =
      IsoGrid(boardWidth: InfiniteEstateScreen.boardSize, boardHeight: InfiniteEstateScreen.boardSize);
  // Rebuilt only when the board or the buildings change.
  VillageScene? _scene;
  List<String?>? _sceneBoard;
  List<BoardStructure>? _sceneStructures;
  Map<String, SpriteMeta> _spriteMeta = const {};
  // Every valid word on the board (repeats included), for tap cards.
  List<WordRun> _wordRuns = const [];
  // The word whose card is open, lit up on the map.
  Set<int> _highlight = const {};
  BoardStructure? _highlightBuilding;
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
    initSpellCheck();
    _landmarkOrder = landmarkBoardIndices(
      InfiniteEstateScreen.boardSize,
      InfiniteEstateScreen.boardSize,
    );
    _islandMap = IslandMap(seed: _mapSeed, homes: const [InfiniteEstateScreen.homeIndex]);
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

  // The first time Village view shows, center it on the middle of all the
  // letters (the board center if there are none).
  void _centerVillageIfNeeded(Size viewportSize, VillageScene scene) {
    if (_villageCentered) return;
    _villageCentered = true;
    final center = scene.lettersCenter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _villageTransform.value = isoTransformCenteredOn(center.r, center.c, viewportSize, 1.0, _isoGrid);
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _villageTransform.dispose();
    super.dispose();
  }

  bool _hasStructure(String magicWord) => _structures.any((s) => s.def.word == magicWord);

  // spec-15: returns a fog overlay color for a board cell index.
  //   - Solid fog (can't see): dark grey, mostly opaque.
  //   - Fuzzy edge (canSee but not cleared): lighter grey, semi-transparent.
  //   - Cleared: null (no overlay); water cells get a subtle blue tint.
  Color? _fogOverlay(int index) {
    if (!_fog.isCleared(index)) {
      if (_fog.canSee(index)) return const Color(0x55888888); // edge haze
      return const Color(0xCC555555); // solid fog
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
    await _saveVillage();

    // Level-up treats (fire at most once per level, in order).
    if (newXp > 0) {
      final levelAfter = levelInfoForXp(ref.read(portfolioProvider).totalXp).level;
      for (var lv = levelBefore + 1; lv <= levelAfter; lv++) {
        if (!_levelTreats.contains(lv)) await _doLevelTreat(lv);
      }
    }
  }

  Future<void> _loadSavedVillage() async {
    final saved = await _saveController.load();
    if (!mounted) return;
    var needsSave = false;
    if (saved != null) {
      // Older saves (21-letter rack) are brought up to the current format
      // first; the extra letters go back to the pool, nothing is lost.
      final migrated = migrateVillageSave(saved, rackSize: InfiniteEstateScreen.rackSize);
      final controller = ref.read(gridGameControllerProvider.notifier);
      controller.restoreState(
        boardCells: migrated.boardCells,
        rackCells: migrated.rackCells,
        pool: migrated.pool,
        dealtLetters: migrated.dealtLetters,
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
      // Build the island map for the restored seed.
      _islandMap = IslandMap(seed: _mapSeed, homes: const [InfiniteEstateScreen.homeIndex]);
      // Restore fog; migration guarantees `cleared` is non-null for v3 saves.
      final clearedB64 = migrated.cleared;
      _fog = clearedB64 != null
          ? FogMap.fromBase64(clearedB64)
          : FogMap.empty();
      needsSave = saved.saveVersion != migrated.saveVersion;
    }
    setState(() => _restoring = false);
    // Write the migrated save straight away so migration only ever runs
    // once.
    if (needsSave) await _saveVillage();
    // Bring score/structures in sync with whatever board we ended up
    // with (restored or fresh).
    await _refreshStructures();
    await _refreshScore();
    await _takeGifts();
  }

  Future<void> _saveVillage() async {
    final gridState = ref.read(gridGameControllerProvider);
    await _saveController.save(VillageSaveData(
      boardCells: gridState.boardCells,
      rackCells: gridState.rackCells,
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
      added.add(controller.addGiftLetter(g.letter!));
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
      final runs = await controller.currentWordRuns(isValid: ref.read(wordCheckProvider));
      if (!mounted) return;
      final structures = computeStructures(runs);
      final newlyDiscovered = newDiscoveries(structures, _discoveredWords);
      setState(() {
        _structures = structures;
        _wordRuns = runs;
        if (newlyDiscovered.isNotEmpty) {
          _discoveredWords = {..._discoveredWords, ...newlyDiscovered};
        }
      });
      if (newlyDiscovered.isNotEmpty) {
        await _saveVillage();
        _celebrateNewBuildings(newlyDiscovered);
      }
      await _processExploreRewards(runs);
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

  // spec-15: hints remaining this visit (Shrine of Sight triples them).
  int get _hintsLeft =>
      (_shrines.contains(ShrineKind.sight) ? 3 : 1) - _hintsUsedThisVisit;

  // spec-15: show a hint SnackBar telling the player the minimum word
  // length needed to push fog into the nearest ring.
  void _doHint() {
    if (_hintsLeft <= 0) return;
    final level = ref.read(settingsProvider).wordLevel;
    const bw = InfiniteEstateScreen.boardSize;
    const homeR = InfiniteEstateScreen.homeIndex ~/ bw;
    const homeC = InfiniteEstateScreen.homeIndex % bw;
    const halfCells = 100;

    Ring? nearestRing;
    var minLen = 999;
    for (var dr = -halfCells; dr <= halfCells; dr++) {
      for (var dc = -halfCells; dc <= halfCells; dc++) {
        final r = homeR + dr;
        final c = homeC + dc;
        if (r < 0 || r >= bw || c < 0 || c >= bw) continue;
        final idx = r * bw + c;
        if (!_fog.canSee(idx)) continue;
        final ring = _islandMap.ringAtIndex(idx);
        if (ring == Ring.coast) continue;
        final len = minLength(ring, level);
        if (len < minLen) {
          minLen = len;
          nearestRing = ring;
        }
      }
    }

    setState(() => _hintsUsedThisVisit++);
    if (!mounted) return;
    final msg = nearestRing == null
        ? 'Keep spelling to clear the fog!'
        : 'Spell a $minLen+ letter word to push into the ${nearestRing.displayName}!';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

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

  // spec-15: open the whole-island map page.
  void _openIslandMap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IslandMapPage(
          islandMap: _islandMap,
          fog: _fog,
          foundSpecialIds: _foundSpecials,
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
    final card = _spriteMeta[defs.first.word]?.cardPath;
    final what = names.length == 1 ? defs.first.description : null;
    _rewardsShowing = showRewardMoment(
      context,
      ribbon: 'New building!',
      title: title,
      message: [
        if (what != null) what,
        'Tap ${names.length == 1 ? 'it' : 'them'} in Village view to see more.',
      ].join('\n'),
      coins: coins,
      picture: card == null ? null : Image.asset(card, fit: BoxFit.contain, excludeFromSemantics: true),
      buttonLabel: 'Hooray!',
      sound: Sfx.building,
    );
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

  // Under the map in Village view (you can't place letters there): a hint
  // line, or the first-building helper until there's a building.
  Widget _villageFooter() {
    if (_structures.isNotEmpty) {
      return Text(
        'Every word you spell is here. Tap one to see what it means.',
        style: WText.label,
        textAlign: TextAlign.center,
      );
    }
    final grid = ref.watch(gridGameControllerProvider);
    final closest = closestBuilding(grid.rackCells, grid.boardCells);
    return FirstBuildingHelper(
      def: closest.def,
      have: closest.have,
      haveEach: closest.haveEach,
      spritePath: _spriteMeta[closest.def.word]?.spritePath,
      onGoToWords: () => _switchView(_ViewMode.words),
    );
  }

  void _drawFromWell() {
    if (_wellUsedThisVisit) return;
    // Only spend the once-per-visit draw if a letter actually arrived
    // (it can't when the pool is empty).
    final gotLetter = ref.read(gridGameControllerProvider.notifier).drawBonusLetter();
    if (gotLetter) setState(() => _wellUsedThisVisit = true);
  }

  // Pans/zooms the Words-view board to center a reached landmark. Switches
  // to Words view first since only GridBoardView (not IsoVillageView) is
  // wired to a TransformationController -- Village view has no meaningful
  // "zoom in on one spot" reading anyway, it's the whole-estate overview.
  void _jumpToLandmark(int boardIndex) {
    setState(() => _viewMode = _ViewMode.words);
    final viewportSize = _boardViewportSize;
    if (viewportSize == null) return;
    _transformController.value = computeCenterTransform(
      viewportSize: viewportSize,
      boardIndex: boardIndex,
      boardWidth: InfiniteEstateScreen.boardSize,
      cellSize: InfiniteEstateScreen.cellSize,
      scale: 1.5,
    );
  }

  // Runs once, the first time the board area's real size is known, to
  // start the player looking at the village's origin instead of the
  // board's empty top-left corner (InteractiveViewer's default).
  void _centerViewIfNeeded(Size viewportSize) {
    if (_viewCentered) return;
    _viewCentered = true;
    // The middle of all the letters (the board center if there are none).
    final center = _villageScene().lettersCenter();
    final centerIndex = center.r * InfiniteEstateScreen.boardSize + center.c;
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

  // Switching views keeps you looking at the same spot, at the same zoom.
  void _switchView(_ViewMode mode) {
    if (mode == _viewMode) return;
    final viewport = _boardViewportSize;
    if (viewport == null) {
      setState(() => _viewMode = mode);
      return;
    }
    if (mode == _ViewMode.village) {
      final cell = centerCellOfFlatView(_transformController.value, viewport, InfiniteEstateScreen.cellSize,
          boardWidth: InfiniteEstateScreen.boardSize, boardHeight: InfiniteEstateScreen.boardSize);
      final scale = transformScale(_transformController.value);
      _villageCentered = true;
      setState(() => _viewMode = mode);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _villageTransform.value =
            isoTransformCenteredOn(cell.r, cell.c, _boardViewportSize ?? viewport, scale, _isoGrid);
      });
    } else {
      final cell = centerCellOfIsoView(_villageTransform.value, viewport, _isoGrid);
      _centerWordsOn(cell.r * InfiniteEstateScreen.boardSize + cell.c, transformScale(_villageTransform.value));
    }
  }

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
    _centerWordsOn(positions[(positions.length - 1) ~/ 2], transformScale(_villageTransform.value));
  }

  Future<String?> _loadDefinition(String word) => ref.read(definitionServiceProvider).getDefinition(word);

  void _onVillageTap(Offset contentPoint) {
    final hit = hitTestVillage(contentPoint, _villageScene());
    switch (hit) {
      case BuildingHit(:final structure):
        _openBuildingCard(structure);
      case CellHit(:final index):
        _openWordCard(index);
      case NoHit():
        break;
    }
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
          'Jump to a landmark',
          _reachedLandmarks.isEmpty
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
    setState(() {
      _highlight = structure.positions;
      _highlightBuilding = structure;
    });
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
    if (mounted) {
      setState(() {
        _highlight = const {};
        _highlightBuilding = null;
      });
    }
  }

  Future<void> _openWordCard(int index) async {
    final runs = _wordRuns.where((r) => r.positions.contains(index)).toList()
      ..sort((a, b) => (a.across ? 0 : 1).compareTo(b.across ? 0 : 1));
    if (runs.isEmpty) {
      await showVillageSheet<void>(context, const NotAWordCard());
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

  void _openBridgeJumpMenu() {
    showDialog(
      context: context,
      builder: (dialogContext) => WordlerDialog(
        title: 'Jump to Landmark',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in _landmarkOrder.asMap().entries)
              if (_reachedLandmarks.contains(entry.value))
                Padding(
                  padding: const EdgeInsets.only(bottom: WSize.gap2),
                  child: ChunkyButton(
                    label: 'Landmark ${entry.key + 1}',
                    icon: Icons.star,
                    kind: ChunkyKind.mode,
                    modeColor: WColors.sun,
                    expand: true,
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _jumpToLandmark(entry.value);
                    },
                  ),
                ),
          ],
        ),
        actions: [
          WordlerDialogAction('Close', () => Navigator.pop(dialogContext), kind: ChunkyKind.secondary),
        ],
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
        WordlerDialogAction('Done', () => Navigator.of(context).popUntil((route) => route.isFirst)),
      ],
    );
    _cashingOut = false;
  }

  @override
  Widget build(BuildContext context) {
    // Recompute which magic words are currently built, and re-save, any
    // time the board/rack/pool changes -- keeps Village view in sync and
    // keeps the persisted village current without the player needing to
    // press anything or remember to save before leaving.
    ref.listen(gridGameControllerProvider, (previous, next) {
      if (previous?.boardCells != next.boardCells) {
        _refreshStructures();
      }
      if (previous != null && previous.rackCells != next.rackCells) {
        _updatePinsAfterRackChange(previous, next);
      }
      if (!_restoring) _saveVillage();
    });

    if (_restoring) {
      return const WordlerScaffold(
        title: 'Infinite Estate',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final stripes = buildingStripes(_structures);

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
                      child: _ViewToggle(
                        mode: _viewMode,
                        onChanged: _switchView,
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
                  showWell: _hasStructure('WELL'),
                  wellUsed: _wellUsedThisVisit,
                  onWell: _drawFromWell,
                  showBridge: _hasStructure('BRIDGE') && _reachedLandmarks.isNotEmpty,
                  onBridge: _openBridgeJumpMenu,
                  buildingCount: _viewMode == _ViewMode.village ? _structures.length : null,
                  // Explains the stripes until there are a few buildings.
                  // Worked out from the live structures, not saved.
                  showStripeHint: _viewMode == _ViewMode.words && _structures.length < 3,
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
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _viewMode == _ViewMode.words
                                  ? GridBoardView(
                                      key: const ValueKey('words'),
                                      theme: _estateTheme,
                                      // Same zoom feel as every other mode's board;
                                      // the generous pan boundary past the lazily-
                                      // built board's own huge extent keeps panning
                                      // to an edge from ever feeling like hitting a
                                      // wall.
                                      minScale: 0.2,
                                      maxScale: 2.5,
                                      boundaryMargin: const EdgeInsets.all(400),
                                      transformController: _transformController,
                                      cellSize: InfiniteEstateScreen.cellSize,
                                      stripes: stripes,
                                      // spec-15: fog overlay and drop gate.
                                      cellOverlay: _fogOverlay,
                                      canDropAt: _fog.canSee,
                                    )
                                  : Builder(builder: (context) {
                                      final scene = _villageScene();
                                      _centerVillageIfNeeded(constraints.biggest, scene);
                                      return IsoVillageView(
                                        key: const ValueKey('village'),
                                        scene: scene,
                                        transformController: _villageTransform,
                                        highlight: _highlight,
                                        highlightBuilding: _highlightBuilding,
                                        onTapContent: _onVillageTap,
                                        minScale: 0.2,
                                        maxScale: 2.5,
                                        boundaryMargin: const EdgeInsets.all(400),
                                        fog: _fog,
                                        islandMap: _islandMap,
                                      );
                                    }),
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
                child: _viewMode == _ViewMode.village
                    ? _villageFooter()
                    : Column(
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
                                    child: GridRackView(
                                      theme: _estateTheme,
                                      crossAxisCount: 5,
                                      childAspectRatio: 1.0,
                                      bordered: false,
                                      cellPadding: 2,
                                      pinnedIndices: _pinnedRackIndices,
                                      onTogglePin: _togglePin,
                                      stripes: {for (final i in _giftRackIndices) i: WColors.sun},
                                    ),
                                  ),
                                ),
                                const SizedBox(width: gap),
                                SizedBox(
                                  width: swapWidth,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _HintButton(
                                        hintsLeft: _hintsLeft,
                                        onHint: _doHint,
                                      ),
                                      const SizedBox(height: 4),
                                      SizedBox(
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

/// Words / Village: a soil track; the selected side is sun-filled with a
/// check mark, so which view you're in is never in doubt.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.mode, required this.onChanged});

  final _ViewMode mode;
  final ValueChanged<_ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget side(_ViewMode value, String label) {
      final selected = mode == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: '$label view',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.center,
              // Keeps the two labels apart when big text shrinks them.
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: selected ? WColors.sun : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: selected ? Border.all(color: WColors.ink, width: WSize.outlineSmall) : null,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) ...[
                      const Icon(Icons.check, size: 18, color: WColors.ink),
                      const SizedBox(width: 4),
                    ],
                    Text(label, style: WText.button.copyWith(color: selected ? WColors.ink : WColors.tile)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: WSize.tapTarget - WSize.lip,
      margin: const EdgeInsets.only(bottom: WSize.lip),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: WColors.soil,
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: BorderRadius.circular(14),
        boxShadow: wLip(WSize.lip),
      ),
      child: Row(
        children: [
          side(_ViewMode.words, 'Words'),
          side(_ViewMode.village, 'Village'),
        ],
      ),
    );
  }
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
    required this.showWell,
    required this.wellUsed,
    required this.onWell,
    required this.showBridge,
    required this.onBridge,
    this.buildingCount,
    this.showStripeHint = false,
  });

  final int score;
  final VoidCallback onScoreTap;
  // spec-15: total XP for the XP chip (replaces the score chip).
  final int totalXp;
  final int discoveredCount;
  final int totalMagicWords;
  final VoidCallback onJournal;
  final bool showWell;
  final bool wellUsed;
  final VoidCallback onWell;
  final bool showBridge;
  final VoidCallback onBridge;
  // Village view only.
  final int? buildingCount;
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
        if (buildingCount != null)
          PillChip(
            icon: Icons.house,
            value: '$buildingCount',
            label: buildingCount == 1 ? 'building' : 'buildings',
            badgeColor: WColors.leaf,
          ),
        PillChip(
          icon: Icons.menu_book,
          value: '$discoveredCount/$totalMagicWords',
          badgeColor: WColors.sun,
          tooltip: 'Journal',
          onTap: onJournal,
        ),
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

// "Hint" button above the Swap column: tells the player the minimum word
// length needed to push fog into the nearest visible ring.
class _HintButton extends StatelessWidget {
  const _HintButton({required this.hintsLeft, required this.onHint});

  final int hintsLeft;
  final VoidCallback onHint;

  @override
  Widget build(BuildContext context) {
    final enabled = hintsLeft > 0;
    final ink = enabled ? WColors.ink : WColors.muted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Hint${enabled ? ", $hintsLeft left" : " used"}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onHint : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: BoxDecoration(
            color: enabled ? WColors.skyTint : WColors.boardCell,
            border: Border.all(color: ink, width: WSize.outline),
            borderRadius: BorderRadius.circular(WSize.radiusButton),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lightbulb_outline, color: enabled ? WColors.sky : WColors.muted, size: 22),
              Text('Hint', style: WText.buttonSmall.copyWith(color: ink)),
              Text(
                enabled ? (hintsLeft > 1 ? 'x$hintsLeft' : '1 left') : 'used',
                style: WText.label.copyWith(color: ink, height: 1.1),
              ),
            ],
          ),
        ),
      ),
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
