import 'package:namer_app/components/timer.dart';
import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../daily/bonus_word_picker.dart';
import '../daily/daily_challenge_controller.dart';
import '../daily/daily_challenge_data.dart';
import '../daily/daily_seed.dart';
import '../daily/daily_tier.dart';
import '../daily/share_card.dart';
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../portfolio/portfolio_controller.dart';
import '../portfolio/property_tier.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/game_layout.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import '../ui/wordler_scaffold.dart';
import 'game_screen.dart' show showCheckResultDialog;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        return const WordlerScaffold(
          title: 'Daily Estate Challenge',
          body: Center(child: CircularProgressIndicator()),
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
    return WordlerScaffold(
      title: 'Daily Estate Challenge',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        child: ChunkyCard(
          hero: true,
          color: WColors.skyTint,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: WColors.grass, size: 64),
              const SizedBox(height: 12),
              const Text("You've already played today!", style: WText.heading, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text('Current streak: ${data.streak} day${data.streak == 1 ? '' : 's'}', style: WText.bodyBold),
              if (result != null) ...[
                const SizedBox(height: 8),
                Text(
                  result.completed
                      ? 'Completed in ${_formatSeconds(result.timeSeconds)} -- ${result.tierAwarded.label}${result.bonusWordFound ? ' (bonus word found!)' : ''}'
                      : "Today's attempt: gave up",
                  style: WText.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ChunkyButton(
                  label: 'Share Result',
                  icon: Icons.share,
                  kind: ChunkyKind.secondary,
                  onPressed: () => _shareResult(context, result, data.streak),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Come back tomorrow for a new puzzle!', style: WText.body, textAlign: TextAlign.center),
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

  void _shareResult(BuildContext context, DailyResult result, int streak) {
    final text = buildDailyShareText(
      dateKey: result.dateKey,
      completed: result.completed,
      timeSeconds: result.timeSeconds,
      streak: streak,
      tier: result.tierAwarded,
      bonusWordFound: result.bonusWordFound,
    );
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Result copied to clipboard!')),
    );
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
    var confirmed = false;
    await showWordlerDialog<void>(
      context,
      title: 'Give up?',
      bodyText: "You won't be able to try again today.",
      actions: [
        WordlerDialogAction('Keep Playing', () {}),
        WordlerDialogAction('Give Up', () => confirmed = true, kind: ChunkyKind.danger),
      ],
    );
    if (!confirmed) return;
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
      showCheckResultDialog(context, result);
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
    showWordlerDialog<void>(
      context,
      title: 'Daily Challenge Complete!',
      barrierDismissible: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Time: ${_stopwatchManager.elapsedTime}'),
          const SizedBox(height: 8),
          Row(children: [
            Icon(tier.icon, color: WColors.ink),
            const SizedBox(width: 8),
            Text('Awarded: ${tier.label}', style: WText.bodyBold),
          ]),
          if (bonusWordFound) ...[
            const SizedBox(height: 8),
            Text("Bonus word found: ${widget.bonusWord!.toUpperCase()}!",
                style: WText.bodyBold.copyWith(color: WColors.grass)),
          ] else if (widget.bonusWord != null) ...[
            const SizedBox(height: 8),
            Text("Today's bonus word was ${widget.bonusWord!.toUpperCase()} -- missed it this time!"),
          ],
        ],
      ),
      actions: [
        WordlerDialogAction('Done', () => Navigator.of(context).popUntil((route) => route.isFirst)),
        WordlerDialogAction('Share', () {
          final text = buildDailyShareText(
            dateKey: dailyDateKey(widget.today),
            completed: true,
            timeSeconds: timeSeconds,
            streak: ref.read(dailyChallengeProvider).streak,
            tier: tier,
            bonusWordFound: bonusWordFound,
          );
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Result copied to clipboard!')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }, kind: ChunkyKind.secondary),
      ],
    );
  }

  // Leaving doesn't record an attempt, so the player can come back later
  // today and start again with the same letters.
  void _confirmLeave() {
    if (_roundEnded) {
      Navigator.of(context).pop();
      return;
    }
    confirmLeaveRound(
      context,
      title: "Leave today's puzzle?",
      body: 'You can come back later today and start again with the same letters.',
      onLeave: _stopwatchManager.stop,
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
        pill: GamePill(label: 'Time', value: _stopwatchManager.elapsedTime, color: WModeColors.daily),
        giveUp: _giveUp,
        onCheck: _onCheckPressed,
      ),
    );
  }
}
