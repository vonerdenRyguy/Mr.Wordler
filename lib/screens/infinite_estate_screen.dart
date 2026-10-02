import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_game_state.dart';
import '../game/grid_providers.dart';
import '../portfolio/portfolio_controller.dart';
import '../stats/mode_stats_controller.dart';
import '../village/bridge_transform.dart';
import '../village/discovery_journal_view.dart';
import '../village/landmark.dart';
import '../village/magic_word.dart';
import '../village/village_board_view.dart';
import '../village/village_save.dart';
import '../village/village_save_migration.dart';

import 'package:flutter/material.dart';
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

// Earthy green/brown palette so Infinite Estate reads as "open land" at a
// glance instead of reusing every other mode's orange/purple board.
const _estateTheme = GridTheme(
  boardColor: Color(0xFFA5D6A7), // soft green plot
  boardBorderColor: Color(0xFF33691E),
  rackColor: Color(0xFF6D4C41), // warm soil brown
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
  DateTime? _lastPopAttempt;
  _ViewMode _viewMode = _ViewMode.words;
  List<BoardStructure> _structures = [];
  bool _computingStructures = false;

  final _saveController = VillageSaveController();
  bool _restoring = true;
  // Kept as both an ordered list (so the Bridge jump dialog can number
  // landmarks in a stable, meaningful order) and a Set (for the O(1)
  // membership checks GridTileWidget/VillageBoardView need every build).
  late final List<int> _landmarkOrder;
  late final Set<int> _landmarkIndices;
  Set<int> _reachedLandmarks = {};
  Set<String> _discoveredWords = {};
  // Rack pinning is a pure UI affordance (no mechanical effect), so it's
  // deliberately not persisted -- it's about tracking intent within a
  // single visit, not a permanent record.
  final Set<int> _pinnedRackIndices = {};

  // Well structure ability: one free bonus letter draw per visit to the
  // village (not per session-open -- reopening the app doesn't reset it,
  // since that would just be a way to farm free letters). Session-only,
  // not persisted.
  bool _wellUsedThisVisit = false;
  // Farm structure ability: the first Swap each visit is free. Works like
  // the Well's limit: session-only, reset when the screen is reopened.
  bool _farmSwapUsedThisVisit = false;

  // Bridge structure ability: drives GridBoardView's InteractiveViewer to
  // jump/pan to a reached landmark. _boardViewportSize is captured by the
  // LayoutBuilder wrapping the board area and used to compute the jump
  // transform (see bridge_transform.dart) -- it's only known once that
  // area has actually been laid out, hence nullable.
  final _transformController = TransformationController();
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
    _landmarkIndices = _landmarkOrder.toSet();
    _loadSavedVillage();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  bool _hasStructure(String magicWord) => _structures.any((s) => s.def.word == magicWord);

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
    if (_pinnedRackIndices.isEmpty) return;
    final before = previous.rackCells;
    final after = next.rackCells;
    final boardChanged = previous.boardCells != next.boardCells;
    final updated = <int>{};
    for (final i in _pinnedRackIndices) {
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
    if (updated.length != _pinnedRackIndices.length || !updated.containsAll(_pinnedRackIndices)) {
      setState(() {
        _pinnedRackIndices
          ..clear()
          ..addAll(updated);
      });
    }
  }

  void _openJournal() {
    final rackCells = ref.read(gridGameControllerProvider).rackCells;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DiscoveryJournalView(
        rackCells: rackCells,
        discoveredWords: _discoveredWords,
      ),
    );
  }

  // A landmark is "reached" the instant a letter lands on its tile.
  // One-time and always positive: a bonus letter draw plus a celebratory
  // message, never a penalty. reachedLandmarks (persisted) guards against
  // firing again on a later visit.
  Future<void> _checkLandmarks() async {
    final boardCells = ref.read(gridGameControllerProvider).boardCells;
    for (final index in _landmarkIndices) {
      if (_reachedLandmarks.contains(index)) continue;
      if (boardCells[index] == null) continue;

      _reachedLandmarks = {..._reachedLandmarks, index};
      final gotLetter = ref.read(gridGameControllerProvider.notifier).drawBonusLetter();
      await _saveVillage();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFFFF9C4),
          title: const Text('🌟 Landmark Discovered!'),
          content: Text(gotLetter
              ? 'Your village has grown to reach a landmark. A bonus letter has been added to the end of your rack!'
              : 'Your village has grown to reach a landmark. Wonderful exploring!'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Wonderful!')),
          ],
        ),
      );
    }
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
      final wordPositions = await controller.currentWordPositions();
      if (!mounted) return;
      final structures = computeStructures(wordPositions);
      final newlyDiscovered = structures
          .map((s) => s.def.word)
          .where((w) => !_discoveredWords.contains(w))
          .toSet();
      setState(() {
        _structures = structures;
        if (newlyDiscovered.isNotEmpty) {
          _discoveredWords = {..._discoveredWords, ...newlyDiscovered};
        }
      });
      if (newlyDiscovered.isNotEmpty) await _saveVillage();
    } finally {
      _computingStructures = false;
    }
  }

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

  bool get _farmSwapAvailable => _hasStructure('FARM') && !_farmSwapUsedThisVisit;

  // Swap letters: pinned letters stay, the rest are traded for balanced
  // draws. The Farm's free swap is used first if available; otherwise it
  // costs swapCost coins, spent only once the swap actually happened.
  void _swapRack() {
    final free = _farmSwapAvailable;
    if (!free && ref.read(portfolioProvider).currency < InfiniteEstateScreen.swapCost) return;
    final swapped = ref.read(gridGameControllerProvider.notifier).swapRack(keepIndices: _pinnedRackIndices);
    if (!swapped) return;
    if (free) {
      setState(() => _farmSwapUsedThisVisit = true);
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

  void _drawFromWell() {
    if (_wellUsedThisVisit) return;
    // Only spend the once-per-visit draw if a letter actually arrived
    // (it can't when the pool is empty).
    final gotLetter = ref.read(gridGameControllerProvider.notifier).drawBonusLetter();
    if (gotLetter) setState(() => _wellUsedThisVisit = true);
  }

  // Pans/zooms the Words-view board to center a reached landmark. Switches
  // to Words view first since only GridBoardView (not VillageBoardView) is
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
    const centerIndex = (InfiniteEstateScreen.boardSize ~/ 2) * InfiniteEstateScreen.boardSize +
        (InfiniteEstateScreen.boardSize ~/ 2);
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

  void _openBridgeJumpMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFDCEDC8),
        title: const Text('Jump to Landmark'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in _landmarkOrder.asMap().entries)
                if (_reachedLandmarks.contains(entry.value))
                  ListTile(
                    leading: Icon(Icons.star, color: Colors.amber.shade800),
                    title: Text('Landmark ${entry.key + 1}'),
                    onTap: () {
                      Navigator.pop(context);
                      _jumpToLandmark(entry.value);
                    },
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFDCEDC8),
        title: const Text('Wrap up for now?'),
        content: Text(earned > 0
            ? 'Cash out $earned points of growth since your last visit? Your village stays exactly as built.'
            : "You haven't grown the village since your last visit, so there's nothing new to cash out -- but your village is saved either way."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Playing')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave Village')),
        ],
      ),
    );
    if (confirmed != true) return;
    _cashingOut = true;

    final isNewHighScore = ref.read(modeStatsProvider.notifier).reportInfiniteEstateScore(_score);
    if (earned > 0) {
      final portfolioController = ref.read(portfolioProvider.notifier);
      portfolioController.addCurrency(earned ~/ 20);
      portfolioController.addXp(earned ~/ 10);
      _lastCashedOutScore = _score;
      await _saveVillage();
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFDCEDC8),
        title: const Text('See You Next Time!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Village score: $_score'),
            if (earned > 0) Text('+${earned ~/ 20} coins, +${earned ~/ 10} XP this visit'),
            if (isNewHighScore) ...[
              const SizedBox(height: 8),
              const Text('New high score!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Done'),
          ),
        ],
      ),
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
        if (!_restoring) _checkLandmarks();
      }
      if (previous != null && previous.rackCells != next.rackCells) {
        _updatePinsAfterRackChange(previous, next);
      }
      if (!_restoring) _saveVillage();
    });

    if (_restoring) {
      return Scaffold(
        appBar: AppBar(title: const Text('Infinite Estate'), backgroundColor: const Color(0xFF33691E)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastPopAttempt != null && now.difference(_lastPopAttempt!) < const Duration(seconds: 2)) {
          Navigator.of(context).pop();
          return;
        }
        _lastPopAttempt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Swipe again to exit -- your village is saved automatically'), duration: Duration(seconds: 2)),
        );
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFFF1F8E9),
        appBar: AppBar(
          backgroundColor: const Color(0xFF33691E),
          foregroundColor: Colors.white,
          // An explicit way out (the double-swipe guard below only covers
          // the system back gesture). Leaving is always safe: the village
          // autosaves after every change.
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Leave village (it saves automatically)',
            onPressed: () => Navigator.of(context).pop(),
          ),
          titleSpacing: 0,
          // Only the view toggle lives in the title now; score and the
          // structure abilities moved to their own row below, so nothing
          // has to be shrunk to fit and text stays full size.
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: SegmentedButton<_ViewMode>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                backgroundColor: const Color(0xFF558B2F),
                foregroundColor: Colors.white,
                selectedBackgroundColor: Colors.white,
                selectedForegroundColor: const Color(0xFF33691E),
                side: const BorderSide(color: Colors.white),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              segments: const [
                ButtonSegment(value: _ViewMode.words, label: Text('Words')),
                ButtonSegment(value: _ViewMode.village, label: Text('Village')),
              ],
              selected: {_viewMode},
              onSelectionChanged: (selection) => setState(() => _viewMode = selection.first),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _endSession,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              child: const Text('End'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _VillageActionBar(
                score: _score,
                onScoreTap: _refreshScore,
                discoveredCount: _discoveredWords.length,
                totalMagicWords: kMagicWords.length,
                onJournal: _openJournal,
                showWell: _hasStructure('WELL'),
                wellUsed: _wellUsedThisVisit,
                onWell: _drawFromWell,
                showBridge: _hasStructure('BRIDGE') && _reachedLandmarks.isNotEmpty,
                onBridge: _openBridgeJumpMenu,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Recorded (not setState'd -- this must never trigger a
                    // rebuild mid-layout) purely so the Bridge jump ability
                    // knows the current viewport size when it's used later.
                    _boardViewportSize = constraints.biggest;
                    _centerViewIfNeeded(constraints.biggest);
                    return AnimatedSwitcher(
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
                              landmarkIndices: _landmarkIndices,
                              transformController: _transformController,
                              cellSize: InfiniteEstateScreen.cellSize,
                            )
                          : VillageBoardView(
                              key: const ValueKey('village'),
                              structures: _structures,
                              landmarkIndices: _landmarkIndices,
                              minScale: 0.2,
                              maxScale: 2.5,
                              boundaryMargin: const EdgeInsets.all(400),
                              cellSize: InfiniteEstateScreen.cellSize,
                            ),
                    );
                  },
                ),
              ),
              // Sized to its content (square tiles, every row visible), so
              // any spare height goes to the board. A bonus letter adds a
              // third row.
              GridRackView(
                theme: _estateTheme,
                crossAxisCount: 5,
                childAspectRatio: 1.0,
                pinnedIndices: _pinnedRackIndices,
                onTogglePin: _togglePin,
              ),
              _SwapButton(
                allPinned: _allBaseSlotsPinned(ref.watch(gridGameControllerProvider.select((s) => s.rackCells))),
                free: _farmSwapAvailable,
                canAfford: ref.watch(portfolioProvider.select((p) => p.currency)) >= InfiniteEstateScreen.swapCost,
                onSwap: _swapRack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// The row under the AppBar: village score plus every structure ability
// and the Journal, as full-size labeled buttons. A Wrap (not a Row) so a
// narrow phone or a large system text size flows onto a second line
// instead of overflowing or shrinking the text.
class _VillageActionBar extends StatelessWidget {
  const _VillageActionBar({
    required this.score,
    required this.onScoreTap,
    required this.discoveredCount,
    required this.totalMagicWords,
    required this.onJournal,
    required this.showWell,
    required this.wellUsed,
    required this.onWell,
    required this.showBridge,
    required this.onBridge,
  });

  final int score;
  final VoidCallback onScoreTap;
  final int discoveredCount;
  final int totalMagicWords;
  final VoidCallback onJournal;
  final bool showWell;
  final bool wellUsed;
  final VoidCallback onWell;
  final bool showBridge;
  final VoidCallback onBridge;

  static const _buttonTextStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.bold);

  @override
  Widget build(BuildContext context) {
    ButtonStyle styleWith(Color background) => OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: const Color(0xFF1B5E20),
          backgroundColor: background,
          side: const BorderSide(color: Color(0xFF81C784)),
          textStyle: _buttonTextStyle,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        );
    final buttonStyle = styleWith(Colors.white);
    return Container(
      width: double.infinity,
      color: const Color(0xFFDCEDC8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Tooltip(
            message: 'Village score (tap to recount)',
            child: OutlinedButton.icon(
              style: buttonStyle,
              onPressed: onScoreTap,
              icon: const Icon(Icons.landscape, size: 20),
              label: Text('$score'),
            ),
          ),
          OutlinedButton.icon(
            style: buttonStyle,
            onPressed: onJournal,
            icon: const Icon(Icons.menu_book, size: 20),
            label: Text('Journal $discoveredCount/$totalMagicWords'),
          ),
          if (showWell)
            OutlinedButton.icon(
              style: styleWith(wellUsed ? Colors.grey.shade200 : const Color(0xFFE1F5FE)),
              onPressed: wellUsed ? null : onWell,
              icon: const Icon(Icons.water_drop, size: 20),
              label: Text(wellUsed ? 'Well used' : 'Free letter'),
            ),
          if (showBridge)
            OutlinedButton.icon(
              style: buttonStyle,
              onPressed: onBridge,
              icon: const Icon(Icons.alt_route, size: 20),
              label: const Text('Jump'),
            ),
        ],
      ),
    );
  }
}

// "Swap letters" under the rack, with a chip saying what it costs. spec-03
// restyles it; this is the plain version.
class _SwapButton extends StatelessWidget {
  const _SwapButton({
    required this.allPinned,
    required this.free,
    required this.canAfford,
    required this.onSwap,
  });

  final bool allPinned;
  final bool free;
  final bool canAfford;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    const cost = InfiniteEstateScreen.swapCost;
    final enabled = !allPinned && (free || canAfford);
    final String? chip = allPinned ? null : (free ? 'Free - Farm' : (canAfford ? '$cost coins' : 'Need $cost coins'));
    final chipColor = !enabled ? Colors.grey.shade600 : (free ? const Color(0xFF2E7D32) : const Color(0xFF6D4C41));
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: enabled ? onSwap : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDCEDC8),
            foregroundColor: const Color(0xFF1B5E20),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.swap_horiz, size: 22),
              const SizedBox(width: 6),
              Flexible(child: Text(allPinned ? 'All letters pinned' : 'Swap letters', overflow: TextOverflow.ellipsis)),
              if (chip != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(12)),
                  child: Text(chip, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
