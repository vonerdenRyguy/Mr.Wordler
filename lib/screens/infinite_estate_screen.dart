import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../portfolio/portfolio_controller.dart';
import '../stats/mode_stats_controller.dart';
import '../village/bridge_transform.dart';
import '../village/discovery_journal_view.dart';
import '../village/landmark.dart';
import '../village/village_board_view.dart';
import '../village/village_save.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ViewMode { words, village }

// Infinite Estate / Village Builder: an endless-feeling session on a large
// (500x500, pannable/zoomable) board -- not literally unbounded, but big
// enough that a normal session never reaches an edge, with the same zoom
// feel as every other mode's board and generous pan range so the space
// reads as open rather than a small fixed grid. The rack refills itself
// the instant a tile leaves it for the board (GridConfig.refillRackOnPlace),
// so there's no separate "trade in" affordance.
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
            rackSize: 21,
            totalPoolSize: totalPoolSize,
            refillRackOnPlace: true,
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
    if (saved != null) {
      ref.read(gridGameControllerProvider.notifier).restoreState(
            boardCells: saved.boardCells,
            rackCells: saved.rackCells,
            pool: saved.pool,
            dealtLetters: saved.dealtLetters,
          );
      _lastCashedOutScore = saved.lastCashedOutScore;
      _reachedLandmarks = saved.reachedLandmarks;
      _discoveredWords = saved.discoveredWords;
    }
    setState(() => _restoring = false);
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
      ref.read(gridGameControllerProvider.notifier).drawBonusLetter();
      await _saveVillage();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFFFF9C4),
          title: const Text('🌟 Landmark Discovered!'),
          content: const Text(
              "Your village has grown to reach a landmark. You've been granted a bonus letter draw!"),
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

  void _drawFromWell() {
    if (_wellUsedThisVisit) return;
    ref.read(gridGameControllerProvider.notifier).drawBonusLetter();
    setState(() => _wellUsedThisVisit = true);
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
        appBar: AppBar(
          toolbarHeight: 90,
          titleSpacing: 4.0,
          // Three variable-width pieces (the Words/Village toggle, a
          // tappable score chip, a labeled button) plus up to two action
          // icons all have to share one toolbar's width. Wrapping each in
          // Flexible+FittedBox lets them shrink together on a narrow
          // phone/large text-scale instead of overflowing the toolbar by
          // a few pixels.
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Lives here (rather than its own row above the board) so
              // that row's height doesn't eat into the board/rack split
              // below and cut rack letters off.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SegmentedButton<_ViewMode>(
                    segments: const [
                      ButtonSegment(value: _ViewMode.words, label: Text('Words'), icon: Icon(Icons.abc)),
                      ButtonSegment(value: _ViewMode.village, label: Text('Village'), icon: Icon(Icons.holiday_village)),
                    ],
                    selected: {_viewMode},
                    onSelectionChanged: (selection) => setState(() => _viewMode = selection.first),
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      // Tapping the score itself re-checks/recalculates it
                      // -- replaces the separate "Score" button so the
                      // toggle above can take its spot.
                      onTap: _refreshScore,
                      borderRadius: BorderRadius.circular(8.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.white),
                            borderRadius: BorderRadius.circular(8.0)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.landscape, color: Colors.green.shade800, size: 18),
                            const SizedBox(width: 6),
                            Text('$_score', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: TextButton.icon(
                    onPressed: _endSession,
                    icon: const Icon(Icons.flag, size: 18, color: Colors.white),
                    label: const Text('End Session', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF33691E),
          automaticallyImplyLeading: false,
          actions: [
            if (_hasStructure('BRIDGE') && _reachedLandmarks.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.alt_route, color: Colors.white),
                tooltip: 'Jump to Landmark',
                onPressed: _openBridgeJumpMenu,
              ),
            IconButton(
              icon: const Icon(Icons.menu_book, color: Colors.white),
              tooltip: 'Discovery Journal',
              onPressed: _openJournal,
            ),
          ],
        ),
        floatingActionButton: _hasStructure('WELL')
            ? FloatingActionButton.extended(
                onPressed: _wellUsedThisVisit ? null : _drawFromWell,
                backgroundColor: _wellUsedThisVisit ? Colors.grey : Colors.lightBlue,
                icon: const Icon(Icons.water_drop),
                label: Text(_wellUsedThisVisit ? 'Well used this visit' : 'Draw from Well'),
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 6,
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
                              preferBalancedRefill: _hasStructure('FARM'),
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
              Expanded(
                flex: 3,
                child: GridRackView(
                  theme: _estateTheme,
                  pinnedIndices: _pinnedRackIndices,
                  onTogglePin: _togglePin,
                ),
              ),
              const Expanded(flex: 1, child: ColoredBox(color: Color(0xFF6D4C41))),
            ],
          ),
        ),
      ),
    );
  }
}
