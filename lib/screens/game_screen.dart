import 'dart:convert';

import 'package:namer_app/components/timer.dart';
import '../components/valid_word_check.dart' show initSpellCheck, WordCheckResult;
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../ui/chunky_button.dart';
import '../ui/game_layout.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';

// Free Play: the original, untimed mode -- empty a 21-letter rack onto a
// 10x10 board with no time limit. Runs on the shared grid-game engine
// (see lib/game/) so its board/rack/validation logic is the same code
// every other mode (Time Attack, Daily Estate Challenge, etc.) uses.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        gridConfigProvider.overrideWithValue(
          const GridConfig(boardWidth: 10, boardHeight: 10, rackSize: 21),
        ),
      ],
      child: const _GameScreenBody(),
    );
  }
}

class _GameScreenBody extends ConsumerStatefulWidget {
  const _GameScreenBody();

  @override
  ConsumerState<_GameScreenBody> createState() => _GameScreenBodyState();
}

class _GameScreenBodyState extends ConsumerState<_GameScreenBody> {
  // Tracks and displays elapsed game time.
  late StopwatchManager _stopwatchManager;

  @override
  void initState() {
    super.initState();
    _stopwatchManager = StopwatchManager(context);
    _stopwatchManager.start();
    initSpellCheck(); // Start loading the dictionary now, not on first Check tap.
  }

  @override
  void dispose() {
    // Stop the stopwatch's periodic timer so it doesn't keep firing
    // (and touching this screen's context) after the player navigates away.
    _stopwatchManager.stop();
    super.dispose();
  }

  void _confirmLeave() {
    confirmLeaveRound(
      context,
      body: "Your board won't be saved.",
      onLeave: _stopwatchManager.stop,
    );
  }

  // Validates the board and shows the matching result: win, words not
  // connected, or the list of words found.
  Future<void> _onCheckPressed() async {
    final controller = ref.read(gridGameControllerProvider.notifier);
    final result = await controller.checkWords();
    // The word check is async; bail out if the player left meanwhile.
    if (!mounted) return;

    // Win condition: every letter the player has been dealt is placed on
    // the board. Read state fresh (post-await) in case a tile moved while
    // the check was running.
    final isWin = ref.read(gridGameControllerProvider).isPoolEmptied;
    if (isWin && result.areValid && result.areConnected) {
      _stopwatchManager.stop();
      final finalTime = _stopwatchManager.getElapsedTime();
      showDialog(context: context, builder: (context) => _WinDialog(winningTime: finalTime, winningWords: result.words));
    } else {
      showCheckResultDialog(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The back gesture asks first, the same as the Leave button.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: GameLayout(
        onLeave: _confirmLeave,
        pill: GamePill(label: 'Time', value: _stopwatchManager.elapsedTime, color: WModeColors.freePlay),
        onCheck: _onCheckPressed,
      ),
    );
  }
}

/// The result of a Check that didn't win: words not all connected, or the
/// words found (valid in green, or invalid in red). Shared by the 10x10
/// modes.
void showCheckResultDialog(BuildContext context, WordCheckResult result) {
  if (!result.areConnected && result.areValid) {
    // Words are valid individually but not all touching.
    showWordlerDialog<void>(
      context,
      title: 'All valid words must be connected',
      actions: [WordlerDialogAction('OK', () {})],
    );
    return;
  }
  showWordlerDialog<void>(
    context,
    title: result.areValid ? 'Valid Words!' : 'Invalid Words:',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final word in result.words)
          Text(word, style: WText.bodyBold.copyWith(color: result.areValid ? WColors.grass : WColors.brick)),
      ],
    ),
    actions: [WordlerDialogAction('OK', () {})],
  );
}

// Win dialog shown when the player successfully places all their letters
// into valid, connected words. Plays a confetti animation and lets the
// player submit their name/time to the local leaderboard (persisted via
// SharedPreferences).
class _WinDialog extends StatefulWidget {
  const _WinDialog({required this.winningTime, required this.winningWords});

  final String winningTime;
  final List<String> winningWords;

  @override
  State<_WinDialog> createState() => _WinDialogState();
}

class _WinDialogState extends State<_WinDialog> {
  final _nameController = TextEditingController();
  final _confettiController = ConfettiController(duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    _confettiController.play();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // Converts a "MM:SS" display string into total seconds so entries can
  // be sorted numerically.
  int _parseTimeToSeconds(String time) {
    final parts = time.split(':');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }
    return 0;
  }

  Future<void> _submit() async {
    final playerName = _nameController.text;
    if (playerName.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      // Load existing leaderboard entries (stored as JSON strings).
      final entries = prefs.getStringList('leaderboardEntries') ?? [];
      var leaderboard = entries.map((e) => Map<String, dynamic>.from(jsonDecode(e) as Map<String, dynamic>)).toList();
      leaderboard.add({
        'name': playerName,
        'time': _parseTimeToSeconds(widget.winningTime),
        'displayTime': widget.winningTime,
      });
      // Sort by time (ascending = fastest first) and keep the top 100.
      leaderboard.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
      if (leaderboard.length > 100) leaderboard = leaderboard.sublist(0, 100);
      await prefs.setStringList('leaderboardEntries', leaderboard.map((e) => jsonEncode(e)).toList());
    }
    // Bail out if the dialog's context is gone after the awaits above.
    if (!mounted) return;
    // Return to the very first route (Home).
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WordlerDialog(
          title: 'You Win!',
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your Time: ${widget.winningTime}', style: WText.bodyBold),
              const SizedBox(height: 10),
              const Text('Winning Words:'),
              ...widget.winningWords.map((word) => Text('- $word')),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                style: WText.body,
                decoration: const InputDecoration(hintText: 'Enter your name'),
              ),
            ],
          ),
          actions: [
            WordlerDialogAction('Submit', _submit),
            WordlerDialogAction('Close', () => Navigator.pop(context), kind: ChunkyKind.secondary),
          ],
        ),
        // Confetti burst overlaid on top of the dialog.
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
            ),
          ),
        ),
      ],
    );
  }
}
