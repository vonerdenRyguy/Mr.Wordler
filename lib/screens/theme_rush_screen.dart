import 'dart:math';

import 'package:namer_app/components/timer.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../game/grid_config.dart';
import '../game/grid_game_state.dart';
import '../game/grid_providers.dart';
import '../portfolio/portfolio_controller.dart';
import '../stats/mode_stats_controller.dart';
import '../theme_rush/theme_category.dart';
import '../ui/mode_start_view.dart';
import '../ui/game_layout.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';

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
      showWordlerDialog<void>(
        context,
        title: 'Theme Word Found!',
        barrierDismissible: false,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Time: ${_stopwatchManager.elapsedTime}'),
            if (isNewBest) ...[
              const SizedBox(height: 8),
              Text('New personal best!', style: WText.bodyBold.copyWith(color: WColors.grass)),
            ],
          ],
        ),
        actions: [
          WordlerDialogAction('Done', () => Navigator.of(context).popUntil((route) => route.isFirst)),
        ],
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
      final best = ref.watch(modeStatsProvider.select((s) => s.themeRushBestSeconds[widget.theme.id]));
      return ModeStartView(
        color: WModeColors.themeRush,
        icon: Icons.category_outlined,
        title: 'Theme Rush',
        description: 'Spell one word that fits the theme.',
        rows: [
          ModeStartRow('?', 'Theme: ${widget.theme.name}'),
          const ModeStartRow('1', 'One word is all you need'),
          const ModeStartRow('⏱', 'Your best time per theme is saved'),
        ],
        stats: [ModeStartStat('Best for ${widget.theme.name}', best == null ? '-' : formatSeconds(best))],
        onStart: _start,
      );
    }

    // The back gesture asks first, the same as the Leave button.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: GameLayout(
        onLeave: _confirmLeave,
        pill: GamePill(label: 'Theme', value: widget.theme.name, color: WModeColors.themeRush),
        secondPill: SizedBox(
          width: 100,
          height: WSize.tapTarget,
          child: GamePill(label: '', value: _stopwatchManager.elapsedTime, color: WColors.card),
        ),
        showLettersLeft: false,
        showActions: false,
      ),
    );
  }

  void _confirmLeave() {
    if (_roundEnded) {
      Navigator.of(context).pop();
      return;
    }
    confirmLeaveRound(
      context,
      body: "This round won't count.",
      onLeave: () {
        _roundEnded = true;
        _stopwatchManager.stop();
      },
    );
  }
}
