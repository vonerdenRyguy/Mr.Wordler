import 'package:namer_app/components/timer.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../game/tile_location.dart';
import '../portfolio/portfolio_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Time Attack: same 10x10/21-letter game as Free Play, but against a
// countdown instead of an open-ended stopwatch. Win by emptying the pool
// into valid, connected words before time runs out; lose if it hits zero
// first. Built on the same shared grid engine as every other mode.
class TimeAttackScreen extends StatelessWidget {
  const TimeAttackScreen({super.key});

  static const Duration timeLimit = Duration(minutes: 3);

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        gridConfigProvider.overrideWithValue(
          const GridConfig(boardWidth: 10, boardHeight: 10, rackSize: 21),
        ),
      ],
      child: const _TimeAttackBody(),
    );
  }
}

class _TimeAttackBody extends ConsumerStatefulWidget {
  const _TimeAttackBody();

  @override
  ConsumerState<_TimeAttackBody> createState() => _TimeAttackBodyState();
}

class _TimeAttackBodyState extends ConsumerState<_TimeAttackBody> {
  late CountdownManager _countdown;
  DateTime? _lastPopAttempt;

  // Guards against both the countdown's onExpired firing and a winning
  // Check press racing each other into showing two dialogs.
  bool _roundEnded = false;

  @override
  void initState() {
    super.initState();
    initSpellCheck();
    _countdown = CountdownManager(
      context,
      duration: TimeAttackScreen.timeLimit,
      onExpired: _onTimeExpired,
    );
    _countdown.start();
  }

  @override
  void dispose() {
    _countdown.stop();
    super.dispose();
  }

  void _onTimeExpired() {
    if (_roundEnded || !mounted) return;
    _roundEnded = true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.orangeAccent,
        title: const Text("Time's Up!"),
        content: const Text("You didn't empty the pool in time."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text("Exit"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const TimeAttackScreen()),
              );
            },
            child: const Text("Try Again"),
          ),
        ],
      ),
    );
  }

  Future<void> _onCheckPressed() async {
    final controller = ref.read(gridGameControllerProvider.notifier);
    final result = await controller.checkWords();
    if (_roundEnded) return;
    if (!mounted) return;

    final isWin = ref.read(gridGameControllerProvider).isPoolEmptied;
    if (isWin && result.areValid && result.areConnected) {
      _roundEnded = true;
      _countdown.stop();

      // Small amount of currency, more for a faster clear -- Time Attack
      // is about quick replayable sessions, not primary progression, so
      // it grants currency rather than a property tile.
      final remainingParts = _countdown.remainingTime.split(':');
      final remainingSeconds =
          (int.tryParse(remainingParts[0]) ?? 0) * 60 + (int.tryParse(remainingParts[1]) ?? 0);
      final coins = 10 + (remainingSeconds ~/ 15);
      ref.read(portfolioProvider.notifier)
        ..addCurrency(coins)
        ..addXp(20);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.orangeAccent,
          title: const Text("You Win!"),
          content: Text("Time remaining: ${_countdown.remainingTime}\n+$coins coins, +20 XP"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text("Exit"),
            ),
          ],
        ),
      );
    } else if (!result.areConnected && result.areValid) {
      showDialog(
        context: context,
        builder: (context) => const AlertDialog(
          backgroundColor: Colors.orangeAccent,
          title: Text('All valid words must be connected'),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.orangeAccent,
          title: Text(result.areValid ? 'Valid Words!' : 'Invalid Words:'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: result.words
                .map((word) => Text(word,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: result.areValid ? Colors.green : Colors.red,
                    )))
                .toList(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastPopAttempt != null &&
            now.difference(_lastPopAttempt!) < const Duration(seconds: 2)) {
          _countdown.stop();
          Navigator.of(context).pop();
          return;
        }
        _lastPopAttempt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Swipe again to exit'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          toolbarHeight: 90,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DragTarget<TileLocation>(
                builder: (context, candidateData, rejectData) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Image.asset('lib_assests/trade.png', height: kToolbarHeight - 5),
                  );
                },
                onWillAcceptWithDetails: (details) {
                  if (details.data.zone != TileZone.rack) return false;
                  final rack = ref.read(gridGameControllerProvider).rackCells;
                  final emptyCount = rack
                      .asMap()
                      .entries
                      .where((e) => e.value == null || e.key == details.data.index)
                      .length;
                  return emptyCount >= 3;
                },
                onAcceptWithDetails: (details) {
                  ref.read(gridGameControllerProvider.notifier).tradeIn(details.data.index);
                },
              ),
              ElevatedButton(
                onPressed: _onCheckPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.green,
                ),
                child: const Text('Check'),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  _countdown.remainingTime,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
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
