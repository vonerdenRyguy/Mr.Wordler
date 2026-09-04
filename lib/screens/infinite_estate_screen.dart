import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../portfolio/portfolio_controller.dart';
import '../stats/mode_stats_controller.dart';
import '../village/village_board_view.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ViewMode { words, village }

// Infinite Estate: an endless-feeling session on a large (60x60, pannable/
// zoomable) board -- not literally unbounded, but big enough that a normal
// session never reaches an edge, with a wide zoom range and generous pan
// boundary so the space reads as open rather than a small fixed grid. The
// rack refills itself the instant a tile leaves it for the board
// (GridConfig.refillRackOnPlace), so there's no separate "trade in"
// affordance and no win condition -- the player just keeps building until
// they choose to end the session.
class InfiniteEstateScreen extends StatelessWidget {
  const InfiniteEstateScreen({super.key});

  // 60x60 = 3,600 cells: a large jump from a 10x10 mode board without
  // eagerly building an amount of tile widgets that risks jank on a phone.
  static const int boardSize = 60;
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
  bool _sessionEnded = false;
  DateTime? _lastPopAttempt;
  _ViewMode _viewMode = _ViewMode.words;
  List<BoardStructure> _structures = [];
  bool _computingStructures = false;

  @override
  void initState() {
    super.initState();
    initSpellCheck();
  }

  // Re-derives which magic words are currently built (see BoardStructure's
  // doc comment: this is a rendering computation over the live board, not
  // a separately persisted structures list). Triggered after every board
  // change via ref.listen in build(); guarded against overlapping runs the
  // same way Theme Rush guards its own auto-check.
  Future<void> _refreshStructures() async {
    if (_computingStructures) return;
    _computingStructures = true;
    try {
      final controller = ref.read(gridGameControllerProvider.notifier);
      final wordPositions = await controller.currentWordPositions();
      if (!mounted) return;
      final structures = computeStructures(wordPositions);
      setState(() => _structures = structures);
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

  Future<void> _endSession() async {
    if (_sessionEnded) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFDCEDC8),
        title: const Text('End session?'),
        content: Text('Final score: $_score'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Playing')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End Session')),
        ],
      ),
    );
    if (confirmed != true) return;
    _sessionEnded = true;

    final isNewHighScore = ref.read(modeStatsProvider.notifier).reportInfiniteEstateScore(_score);
    final portfolioController = ref.read(portfolioProvider.notifier);
    portfolioController.addCurrency(_score ~/ 20);
    portfolioController.addXp(_score ~/ 10);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFDCEDC8),
        title: const Text('Session Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Final score: $_score'),
            Text('+${_score ~/ 20} coins, +${_score ~/ 10} XP'),
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
  }

  @override
  Widget build(BuildContext context) {
    // Recompute which magic words are currently built any time the board
    // changes, so Village view stays in sync with Words view without the
    // player needing to press anything.
    ref.listen(gridGameControllerProvider, (previous, next) {
      if (previous?.boardCells != next.boardCells) {
        _refreshStructures();
      }
    });

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
          const SnackBar(content: Text('Swipe again to exit (use End Session to save your score)'), duration: Duration(seconds: 2)),
        );
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          toolbarHeight: 90,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: _refreshScore,
                icon: const Icon(Icons.calculate, size: 18),
                label: const Text('Score'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.lightGreenAccent, foregroundColor: Colors.green.shade900),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(8.0)),
                child: Row(
                  children: [
                    Icon(Icons.landscape, color: Colors.green.shade800, size: 18),
                    const SizedBox(width: 6),
                    Text('$_score', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _endSession,
                icon: const Icon(Icons.flag, size: 18, color: Colors.white),
                label: const Text('End Session', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF33691E),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: SegmentedButton<_ViewMode>(
                  segments: const [
                    ButtonSegment(value: _ViewMode.words, label: Text('Words'), icon: Icon(Icons.abc)),
                    ButtonSegment(value: _ViewMode.village, label: Text('Village'), icon: Icon(Icons.holiday_village)),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (selection) => setState(() => _viewMode = selection.first),
                ),
              ),
              Expanded(
                flex: 6,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _viewMode == _ViewMode.words
                      ? const GridBoardView(
                          key: ValueKey('words'),
                          theme: _estateTheme,
                          // A wide zoom range and generous pan boundary make a
                          // bounded-but-large board feel open: zoomed all the
                          // way out, the whole estate is a distant patchwork;
                          // panning past the built edges still shows empty
                          // space to grow into rather than stopping dead at
                          // the boundary.
                          minScale: 0.06,
                          maxScale: 3.0,
                          boundaryMargin: EdgeInsets.all(600),
                        )
                      : VillageBoardView(key: const ValueKey('village'), structures: _structures),
                ),
              ),
              Expanded(flex: 3, child: GridRackView(theme: _estateTheme)),
              const Expanded(flex: 1, child: ColoredBox(color: Color(0xFF6D4C41))),
            ],
          ),
        ),
      ),
    );
  }
}
