import 'dart:math';

import 'package:namer_app/components/timer.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_game_state.dart';
import '../game/grid_providers.dart';
import '../portfolio/portfolio_controller.dart';
import '../stats/mode_stats_controller.dart';
import '../theme_rush/theme_category.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Theme Rush: a short, replayable race to place one valid, connected word
// matching a randomly-picked theme. The timer stops the instant such a
// word appears on the board (checked automatically after every tile
// move, not just on a manual Check press), not when the player presses
// anything.
class ThemeRushScreen extends StatefulWidget {
  const ThemeRushScreen({super.key});

  @override
  State<ThemeRushScreen> createState() => _ThemeRushScreenState();
}

class _ThemeRushScreenState extends State<ThemeRushScreen> {
  late final ThemeCategory _theme;

  @override
  void initState() {
    super.initState();
    _theme = kThemeCategories[Random().nextInt(kThemeCategories.length)];
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        gridConfigProvider.overrideWithValue(
          const GridConfig(boardWidth: 10, boardHeight: 10, rackSize: 21),
        ),
      ],
      child: _ThemeRushBody(theme: _theme),
    );
  }
}

class _ThemeRushBody extends ConsumerStatefulWidget {
  const _ThemeRushBody({required this.theme});

  final ThemeCategory theme;

  @override
  ConsumerState<_ThemeRushBody> createState() => _ThemeRushBodyState();
}

class _ThemeRushBodyState extends ConsumerState<_ThemeRushBody> {
  bool _started = false;
  bool _roundEnded = false;
  bool _checking = false;
  late StopwatchManager _stopwatchManager;
  DateTime? _lastPopAttempt;

  @override
  void initState() {
    super.initState();
    initSpellCheck();
    _stopwatchManager = StopwatchManager(context);
  }

  @override
  void dispose() {
    _stopwatchManager.stop();
    super.dispose();
  }

  void _start() {
    setState(() => _started = true);
    _stopwatchManager.start();
  }

  Future<void> _checkForThemeWord(GridGameState state) async {
    if (_roundEnded || _checking || !_started) return;
    _checking = true;
    try {
      final controller = ref.read(gridGameControllerProvider.notifier);
      final result = await controller.checkWords();
      if (_roundEnded || !mounted) return;
      if (!result.areValid || !result.areConnected) return;

      final foundThemeWord = result.words
          .map((w) => w.toUpperCase())
          .any((w) => widget.theme.words.contains(w));
      if (!foundThemeWord) return;

      _roundEnded = true;
      _stopwatchManager.stop();
      final elapsedParts = _stopwatchManager.elapsedTime.split(':');
      final seconds =
          (int.tryParse(elapsedParts[0]) ?? 0) * 60 + (int.tryParse(elapsedParts[1]) ?? 0);

      final isNewBest = ref.read(modeStatsProvider.notifier).reportThemeRushTime(widget.theme.id, seconds);
      final portfolioController = ref.read(portfolioProvider.notifier);
      portfolioController.addCurrency(isNewBest ? 15 : 10);
      portfolioController.addXp(isNewBest ? 30 : 20);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.orangeAccent,
          title: const Text('Theme Word Found!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Time: ${_stopwatchManager.elapsedTime}'),
              if (isNewBest) ...[
                const SizedBox(height: 8),
                const Text('New personal best!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
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
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-checks the board after every tile move (not just on a manual
    // button press) so the timer stops the instant a themed word appears.
    ref.listen(gridGameControllerProvider, (previous, next) {
      if (previous?.boardCells != next.boardCells) {
        _checkForThemeWord(next);
      }
    });

    if (!_started) {
      return Scaffold(
        appBar: AppBar(title: const Text('Theme Rush'), backgroundColor: Colors.deepPurple),
        backgroundColor: Colors.orangeAccent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Today's theme:", style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                Text(widget.theme.name,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                const SizedBox(height: 24),
                const Text('Place one valid, connected word matching the theme as fast as you can.'),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _start,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.green),
                  child: const Text('Start'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastPopAttempt != null && now.difference(_lastPopAttempt!) < const Duration(seconds: 2)) {
          _stopwatchManager.stop();
          Navigator.of(context).pop();
          return;
        }
        _lastPopAttempt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Swipe again to exit'), duration: Duration(seconds: 2)),
        );
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          toolbarHeight: 90,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Theme', style: TextStyle(fontSize: 10, color: Colors.white70)),
                  Text(widget.theme.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                    color: Colors.orangeAccent,
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(8.0)),
                child: Text(_stopwatchManager.elapsedTime, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          backgroundColor: Colors.deepPurple,
          automaticallyImplyLeading: false,
        ),
        body: const SafeArea(
          child: Column(
            children: [
              Expanded(flex: 5, child: GridBoardView()),
              Expanded(flex: 3, child: GridRackView()),
              Expanded(flex: 1, child: ColoredBox(color: Colors.orangeAccent)),
            ],
          ),
        ),
      ),
    );
  }
}
