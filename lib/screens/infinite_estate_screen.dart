import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../portfolio/portfolio_controller.dart';
import '../stats/mode_stats_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Infinite Estate: an endless, unbounded-feeling session on a large
// (25x25, pannable/zoomable) board. The rack refills itself the instant a
// tile leaves it for the board (GridConfig.refillRackOnPlace), so there's
// no separate "trade in" affordance and no win condition -- the player
// just keeps building until they choose to end the session.
class InfiniteEstateScreen extends StatelessWidget {
  const InfiniteEstateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        gridConfigProvider.overrideWithValue(
          const GridConfig(
            boardWidth: 25,
            boardHeight: 25,
            rackSize: 21,
            totalPoolSize: 720,
            refillRackOnPlace: true,
          ),
        ),
      ],
      child: const _InfiniteEstateBody(),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    initSpellCheck();
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
        backgroundColor: Colors.orangeAccent,
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
        backgroundColor: Colors.orangeAccent,
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
              ElevatedButton(
                onPressed: _refreshScore,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.green),
                child: const Text('Check Score'),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                    color: Colors.orangeAccent,
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(8.0)),
                child: Text('Score: $_score', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: _endSession,
                child: const Text('End Session', style: TextStyle(color: Colors.white)),
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
