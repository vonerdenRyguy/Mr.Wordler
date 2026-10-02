import 'package:namer_app/components/timer.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../portfolio/portfolio_controller.dart';
import '../ui/chunky_button.dart';
import '../ui/game_layout.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import 'game_screen.dart' show showCheckResultDialog;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Time Attack: same 10x10/21-letter game as Free Play, but against a
// countdown instead of an open-ended stopwatch. Win by emptying the pool
// into valid, connected words before time runs out; lose if it hits zero
// first. Built on the same shared grid engine as every other mode.
class TimeAttackScreen extends StatelessWidget {
  const TimeAttackScreen({super.key});

  static const Duration timeLimit = Duration(minutes: 3);

  // Shown on the start page; not saved, so it resets when the app does.
  static String? lastResultThisSession;

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
    TimeAttackScreen.lastResultThisSession = "Time's up";
    showWordlerDialog<void>(
      context,
      title: "Time's Up!",
      bodyText: "You didn't empty the pool in time.",
      barrierDismissible: false,
      actions: [
        WordlerDialogAction('Try Again', () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const TimeAttackScreen()),
          );
        }),
        WordlerDialogAction('Exit', () => Navigator.of(context).popUntil((route) => route.isFirst),
            kind: ChunkyKind.secondary),
      ],
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
      TimeAttackScreen.lastResultThisSession = 'Won, ${_countdown.remainingTime} left';

      // Small amount of currency, more for a faster clear -- Time Attack
      // is about quick replayable sessions, not primary progression, so
      // it grants currency rather than a property tile.
      final remainingSeconds = _remainingSeconds;
      final coins = 10 + (remainingSeconds ~/ 15);
      ref.read(portfolioProvider.notifier)
        ..addCurrency(coins)
        ..addXp(20);

      showWordlerDialog<void>(
        context,
        title: 'You Win!',
        bodyText: 'Time remaining: ${_countdown.remainingTime}\n+$coins coins, +20 XP',
        barrierDismissible: false,
        actions: [
          WordlerDialogAction('Exit', () => Navigator.of(context).popUntil((route) => route.isFirst)),
        ],
      );
    } else {
      showCheckResultDialog(context, result);
    }
  }

  int get _remainingSeconds {
    final parts = _countdown.remainingTime.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  void _confirmLeave() {
    if (_roundEnded) {
      Navigator.of(context).pop();
      return;
    }
    confirmLeaveRound(
      context,
      body: "The clock stops and this round won't count.",
      onLeave: () {
        _roundEnded = true;
        _countdown.stop();
      },
    );
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
        pill: GamePill(
          label: 'Time left',
          value: _countdown.remainingTime,
          color: WModeColors.timeAttack,
          alert: _remainingSeconds <= 30,
        ),
        onCheck: _onCheckPressed,
      ),
    );
  }
}
