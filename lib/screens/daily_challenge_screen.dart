import 'package:namer_app/components/timer.dart';
import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../daily/bonus_word_picker.dart';
import '../daily/daily_challenge_controller.dart';
import '../daily/daily_seed.dart';
import '../daily/daily_tier.dart';
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../game/tile_location.dart';
import '../portfolio/portfolio_controller.dart';
import '../portfolio/property_tier.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The flagship mode: everyone gets the same 21-letter bank on a given
// UTC calendar date (see daily_seed.dart), with a hidden bonus word
// guaranteed formable from that day's letters. One attempt per day --
// completing or giving up locks today out; simply leaving without either
// does not (see the class doc below for that tradeoff).
class DailyChallengeScreen extends ConsumerStatefulWidget {
  const DailyChallengeScreen({
    super.key,
    @visibleForTesting this.dictionaryLoader,
  });

  // Overridable only for tests -- see pickBonusWord's doc comment for why
  // (flutter_test's mocked asset channel can't handle the real ~1.5MB
  // dictionary file).
  final Future<String> Function()? dictionaryLoader;

  @override
  ConsumerState<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

enum _LoadState { loading, alreadyPlayedToday, ready }

class _DailyChallengeScreenState extends ConsumerState<DailyChallengeScreen> {
  _LoadState _loadState = _LoadState.loading;
  late DateTime _today;
  late int _seed;
  String? _bonusWord;
  List<String> _dealtLetters = [];

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _seed = dailySeedForDate(_today);
    _prepare();
  }

  Future<void> _prepare() async {
    // ConsumerState's `ref` (unlike ProviderScope.containerOf(context)) is
    // safe to read in initState -- it doesn't rely on
    // dependOnInheritedWidgetOfExactType, which asserts if called before
    // the widget has finished mounting.
    final alreadyPlayed = ref.read(dailyChallengeProvider.notifier).hasPlayedToday(_today);
    if (alreadyPlayed) {
      setState(() => _loadState = _LoadState.alreadyPlayedToday);
      return;
    }

    // Independently reproduce the exact same deterministic deal the grid
    // engine will make for this seed (see GridGameController), so the
    // bonus word is guaranteed formable from precisely what's dealt.
    final pool = LetterGenerator.generateLetters(144, seed: _seed);
    _dealtLetters = pool.sublist(0, 21);
    initSpellCheck();
    _bonusWord = widget.dictionaryLoader != null
        ? await pickBonusWord(_dealtLetters, _seed, loadDictionary: widget.dictionaryLoader!)
        : await pickBonusWord(_dealtLetters, _seed);

    if (!mounted) return;
    setState(() => _loadState = _LoadState.ready);
  }

  @override
  Widget build(BuildContext context) {
    switch (_loadState) {
      case _LoadState.loading:
        return Scaffold(
          appBar: AppBar(title: const Text('Daily Estate Challenge'), backgroundColor: Colors.deepPurple),
          body: const Center(child: CircularProgressIndicator()),
        );
      case _LoadState.alreadyPlayedToday:
        return const _AlreadyPlayedView();
      case _LoadState.ready:
        return ProviderScope(
          overrides: [
            gridConfigProvider.overrideWithValue(
              GridConfig(boardWidth: 10, boardHeight: 10, rackSize: 21, randomSeed: _seed),
            ),
          ],
          child: _DailyChallengeBody(bonusWord: _bonusWord, today: _today),
        );
    }
  }
}

class _AlreadyPlayedView extends ConsumerWidget {
  const _AlreadyPlayedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dailyChallengeProvider);
    final result = data.lastResult;
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Estate Challenge'), backgroundColor: Colors.deepPurple),
      backgroundColor: Colors.orangeAccent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.deepPurple, size: 64),
              const SizedBox(height: 16),
              const Text("You've already played today!",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              const SizedBox(height: 12),
              Text('Current streak: ${data.streak} day${data.streak == 1 ? '' : 's'}'),
              if (result != null) ...[
                const SizedBox(height: 8),
                Text(result.completed
                    ? 'Completed in ${_formatSeconds(result.timeSeconds)} -- ${result.tierAwarded.label}${result.bonusWordFound ? ' (bonus word found!)' : ''}'
                    : "Today's attempt: gave up"),
              ],
              const SizedBox(height: 20),
              const Text('Come back tomorrow for a new puzzle!'),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSeconds(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _DailyChallengeBody extends ConsumerStatefulWidget {
  const _DailyChallengeBody({required this.bonusWord, required this.today});

  final String? bonusWord;
  final DateTime today;

  @override
  ConsumerState<_DailyChallengeBody> createState() => _DailyChallengeBodyState();
}

class _DailyChallengeBodyState extends ConsumerState<_DailyChallengeBody> {
  late StopwatchManager _stopwatchManager;
  DateTime? _lastPopAttempt;
  bool _roundEnded = false;

  @override
  void initState() {
    super.initState();
    _stopwatchManager = StopwatchManager(context);
    _stopwatchManager.start();
  }

  @override
  void dispose() {
    _stopwatchManager.stop();
    super.dispose();
  }

  int get _elapsedSeconds {
    final parts = _stopwatchManager.elapsedTime.split(':');
    final minutes = int.tryParse(parts[0]) ?? 0;
    final seconds = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return minutes * 60 + seconds;
  }

  Future<void> _giveUp() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.orangeAccent,
        title: const Text('Give up?'),
        content: const Text("You won't be able to try again today."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Playing')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Give Up')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_roundEnded) return;
    _roundEnded = true;
    _stopwatchManager.stop();
    ref.read(dailyChallengeProvider.notifier).recordAttempt(
          now: widget.today,
          completed: false,
          timeSeconds: _elapsedSeconds,
          bonusWordFound: false,
          tierAwarded: PropertyTier.empty,
        );
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _onCheckPressed() async {
    final controller = ref.read(gridGameControllerProvider.notifier);
    final result = await controller.checkWords();
    if (_roundEnded) return;
    if (!mounted) return;

    final isWin = ref.read(gridGameControllerProvider).isPoolEmptied;
    if (!(isWin && result.areValid && result.areConnected)) {
      if (!result.areConnected && result.areValid) {
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
                          color: result.areValid ? Colors.green : Colors.red)))
                  .toList(),
            ),
          ),
        );
      }
      return;
    }

    _roundEnded = true;
    _stopwatchManager.stop();
    final timeSeconds = _elapsedSeconds;
    final bonusWordFound = widget.bonusWord != null &&
        result.words.map((w) => w.toUpperCase()).contains(widget.bonusWord!.toUpperCase());
    final tier = tierForDailyResult(
      completed: true,
      time: Duration(seconds: timeSeconds),
      bonusWordFound: bonusWordFound,
    );

    ref.read(dailyChallengeProvider.notifier).recordAttempt(
          now: widget.today,
          completed: true,
          timeSeconds: timeSeconds,
          bonusWordFound: bonusWordFound,
          tierAwarded: tier,
        );

    final portfolioController = ref.read(portfolioProvider.notifier);
    final portfolioData = ref.read(portfolioProvider);
    awardDailyTileToPortfolio(portfolioController, portfolioData, tier);
    portfolioController.addXp(bonusWordFound ? 150 : 100);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.orangeAccent,
        title: const Text('Daily Challenge Complete!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Time: ${_stopwatchManager.elapsedTime}'),
            const SizedBox(height: 8),
            Row(children: [
              Icon(tier.icon, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text('Awarded: ${tier.label}'),
            ]),
            if (bonusWordFound) ...[
              const SizedBox(height: 8),
              Text("Bonus word found: ${widget.bonusWord!.toUpperCase()}!",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ] else if (widget.bonusWord != null) ...[
              const SizedBox(height: 8),
              Text("Today's bonus word was ${widget.bonusWord!.toUpperCase()} -- missed it this time!"),
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
          _stopwatchManager.stop();
          Navigator.of(context).pop();
          return;
        }
        _lastPopAttempt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Swipe again to exit (progress is not saved)'), duration: Duration(seconds: 2)),
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
                    decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(8.0)),
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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.green),
                child: const Text('Check'),
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
          actions: [
            TextButton(
              onPressed: _giveUp,
              child: const Text('Give Up', style: TextStyle(color: Colors.white)),
            ),
          ],
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
