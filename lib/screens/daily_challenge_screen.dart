import 'dart:math';

import 'package:namer_app/components/timer.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../daily/daily_challenge_controller.dart';
import '../daily/daily_challenge_data.dart';
import '../daily/daily_puzzle.dart';
import '../daily/daily_seed.dart';
import '../daily/daily_tier.dart';
import '../daily/share_card.dart';
import '../dictionary/definition_service.dart';
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../game/word_landing_banner.dart';
import '../portfolio/portfolio_controller.dart';
import '../portfolio/property_tier.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/game_layout.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import '../ui/wordler_scaffold.dart';
import '../ui/check_result_dialog.dart';
import '../village/village_cards.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The Daily puzzle: everyone gets the same theme, secret word and 21
// letters on a given UTC calendar date (see daily_puzzle.dart). There is no
// Swap and no draw pool -- those 21 letters are the whole round -- and a
// Clue button helps find the secret word. One attempt per day: completing
// or giving up locks today out; simply leaving does not.
class DailyChallengeScreen extends ConsumerStatefulWidget {
  const DailyChallengeScreen({super.key, @visibleForTesting this.today});

  // Overridable only for tests, so a test can pick the day's puzzle.
  final DateTime? today;

  @override
  ConsumerState<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends ConsumerState<DailyChallengeScreen> {
  late final DateTime _today;
  late final DailyPuzzle _puzzle;
  late final bool _alreadyPlayed;

  @override
  void initState() {
    super.initState();
    _today = widget.today ?? DateTime.now();
    _puzzle = dailyPuzzleFor(_today);
    // ConsumerState's `ref` (unlike ProviderScope.containerOf(context)) is
    // safe to read in initState.
    _alreadyPlayed = ref.read(dailyChallengeProvider.notifier).hasPlayedToday(_today);
    if (!_alreadyPlayed) initSpellCheck();
  }

  @override
  Widget build(BuildContext context) {
    if (_alreadyPlayed) return const _AlreadyPlayedView();
    final secret = _puzzle.secretWord;
    return ProviderScope(
      overrides: [
        gridConfigProvider.overrideWithValue(
          GridConfig(
            boardWidth: 10,
            boardHeight: 10,
            rackSize: kDailyLetterCount,
            initialRack: _puzzle.letters,
          ),
        ),
        landingNoteProvider.overrideWithValue((word) => word.toUpperCase() == secret ? 'Secret word!' : null),
      ],
      child: _DailyChallengeBody(puzzle: _puzzle, today: _today),
    );
  }
}

String _formatSeconds(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class _AlreadyPlayedView extends ConsumerWidget {
  const _AlreadyPlayedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dailyChallengeProvider);
    final result = data.lastResult;
    final secret = result?.secretWord;
    return WordlerScaffold(
      title: 'Daily puzzle',
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
              // A result saved by an older build has no theme or secret word.
              if (result?.themeName != null) ...[
                const SizedBox(height: 8),
                Text('Theme: ${result!.themeName}', style: WText.body, textAlign: TextAlign.center),
              ],
              if (secret != null) ...[
                const SizedBox(height: 4),
                Text('Secret word: $secret', style: WText.bodyBold, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                ChunkyButton(
                  label: 'What it means',
                  kind: ChunkyKind.secondary,
                  size: ChunkySize.small,
                  onPressed: () => showVillageSheet<void>(
                    context,
                    MeaningCard(
                      word: secret,
                      loadDefinition: ref.read(definitionServiceProvider).getDefinition,
                    ),
                  ),
                ),
              ],
              if (result != null) ...[
                const SizedBox(height: 8),
                Text(
                  result.completed
                      ? 'Completed in ${_formatSeconds(result.timeSeconds)} -- ${result.tierAwarded.label}${result.bonusWordFound ? ' (secret word found!)' : ''}'
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

  void _shareResult(BuildContext context, DailyResult result, int streak) {
    final text = buildDailyShareText(
      dateKey: result.dateKey,
      completed: result.completed,
      timeSeconds: result.timeSeconds,
      streak: streak,
      tier: result.tierAwarded,
      bonusWordFound: result.bonusWordFound,
      themeName: result.themeName,
      cluesUsed: result.cluesUsed,
    );
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Result copied to clipboard!')),
    );
  }
}

class _DailyChallengeBody extends ConsumerStatefulWidget {
  const _DailyChallengeBody({required this.puzzle, required this.today});

  final DailyPuzzle puzzle;
  final DateTime today;

  @override
  ConsumerState<_DailyChallengeBody> createState() => _DailyChallengeBodyState();
}

class _DailyChallengeBodyState extends ConsumerState<_DailyChallengeBody> {
  late StopwatchManager _stopwatchManager;
  bool _roundEnded = false;
  // Set the first time the secret word is spelled on the board. It stays
  // set if the word is broken up again (the player knows it now); the bonus
  // itself needs the word on the board at the final Check.
  bool _secretFound = false;
  // Clue 2 had no meaning to show (offline), so it gave the last letter.
  bool _lastLetterShown = false;

  String get _secret => widget.puzzle.secretWord;

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

  int get _cluesUsed => ref.read(dailyChallengeProvider.notifier).cluesUsedToday(widget.today);

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
          themeName: widget.puzzle.theme.name,
          secretWord: _secret,
          cluesUsed: _cluesUsed,
        );
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // The meaning for clue 2, with the word itself hidden, or null when
  // there's nothing to show (offline, or no entry).
  Future<String?> _loadClueMeaning() async {
    final meaning = await ref.read(definitionServiceProvider).getDefinition(_secret);
    if (meaning == null || meaning.isEmpty) {
      if (mounted) setState(() => _lastLetterShown = true);
      return null;
    }
    return hideWordInMeaning(meaning, _secret);
  }

  Future<void> _onClue() async {
    if (_roundEnded || _secretFound) return;
    final used = _cluesUsed;
    if (used >= 3) return;

    if (used == 2) {
      var show = false;
      await showWordlerDialog<void>(
        context,
        title: 'Show the whole word?',
        bodyText: 'This is your last clue. You still get a bonus for spelling it.',
        actions: [
          WordlerDialogAction('Not yet', () {}, kind: ChunkyKind.secondary),
          WordlerDialogAction('Show it', () => show = true),
        ],
      );
      if (!show || !mounted) return;
    }

    final clue = ref.read(dailyChallengeProvider.notifier).useClue(widget.today);
    setState(() {});
    final gotIt = [WordlerDialogAction('Got it', () {})];
    switch (clue) {
      case 1:
        await showWordlerDialog<void>(
          context,
          title: 'First letter',
          bodyText: 'It starts with ${_secret[0]}.',
          actions: gotIt,
        );
      case 2:
        final meaning = _loadClueMeaning();
        await showWordlerDialog<void>(
          context,
          title: 'What it means',
          body: FutureBuilder<String?>(
            future: meaning,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Text('Looking it up...', style: WText.body.copyWith(color: WColors.muted));
              }
              return Text(snapshot.data ?? 'It ends with ${_secret[_secret.length - 1]}.', style: WText.body);
            },
          ),
          actions: gotIt,
        );
      default:
        await showWordlerDialog<void>(
          context,
          title: 'The secret word',
          bodyText: "It's $_secret. Spell it on the board to earn the bonus.",
          actions: gotIt,
        );
    }
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
    final cluesUsed = _cluesUsed;
    final secretFound = result.words.map((w) => w.toUpperCase()).contains(_secret);
    final tier = tierForDailyResult(
      completed: true,
      time: Duration(seconds: timeSeconds),
      bonusWordFound: secretFound,
    );
    final coins = secretFound ? secretWordCoins(cluesUsed) : 0;

    ref.read(dailyChallengeProvider.notifier).recordAttempt(
          now: widget.today,
          completed: true,
          timeSeconds: timeSeconds,
          bonusWordFound: secretFound,
          tierAwarded: tier,
          themeName: widget.puzzle.theme.name,
          secretWord: _secret,
          cluesUsed: cluesUsed,
        );

    final portfolioController = ref.read(portfolioProvider.notifier);
    final portfolioData = ref.read(portfolioProvider);
    awardDailyTileToPortfolio(portfolioController, portfolioData, tier);
    portfolioController.addXp(secretFound ? 150 : 100);
    if (coins > 0) portfolioController.addCurrency(coins);

    if (!mounted) return;
    final definitions = ref.read(definitionServiceProvider);
    showWordlerDialog<void>(
      context,
      title: 'Daily puzzle complete!',
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
          const SizedBox(height: 8),
          Text('Theme: ${widget.puzzle.theme.name}'),
          const SizedBox(height: 8),
          if (secretFound)
            Text('Secret word found: $_secret! +$coins coins', style: WText.bodyBold.copyWith(color: WColors.grass))
          else ...[
            Text('The secret word was $_secret.', style: WText.bodyBold),
            FutureBuilder<String?>(
              future: definitions.getDefinition(_secret),
              builder: (context, snapshot) {
                final meaning = snapshot.data;
                if (meaning == null || meaning.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(meaning, style: WText.body.copyWith(color: WColors.muted)),
                );
              },
            ),
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
            bonusWordFound: secretFound,
            themeName: widget.puzzle.theme.name,
            cluesUsed: cluesUsed,
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
  // today and start again with the same letters (and the same clues used).
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
    final cluesUsed = ref.watch(dailyChallengeProvider).cluesUsedOn(dailyDateKey(widget.today));

    ref.listen<List<String?>>(gridGameControllerProvider.select((s) => s.boardCells), (prev, next) {
      if (_secretFound || !boardContainsWord(next, 10, 10, _secret)) return;
      setState(() => _secretFound = true);
    });

    final revealed = <int>{
      if (cluesUsed >= 1) 0,
      if (_lastLetterShown) _secret.length - 1,
      if (cluesUsed >= 3 || _secretFound)
        for (int i = 0; i < _secret.length; i++) i,
    };
    final clueStatus = _secretFound
        ? 'Found'
        : switch (min(cluesUsed, 3)) { 0 => '3 left', 1 => '2 left', 2 => '1 left', _ => 'No more' };

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
        header: SecretWordStrip(
          themeName: widget.puzzle.theme.name,
          secretWord: _secret,
          revealed: revealed,
          found: _secretFound,
        ),
        leading: ClueButton(
          status: clueStatus,
          onPressed: (_secretFound || cluesUsed >= 3) ? null : _onClue,
        ),
        actionHint: 'Find the secret word for a bonus.',
      ),
    );
  }
}

/// The strip above the Daily's board: the theme, and one slot per letter of
/// the secret word (empty, shown by a clue, or all gold once it's found).
class SecretWordStrip extends StatelessWidget {
  const SecretWordStrip({
    super.key,
    required this.themeName,
    required this.secretWord,
    required this.revealed,
    required this.found,
  });

  final String themeName;
  final String secretWord;
  final Set<int> revealed;
  final bool found;

  String get _semantics {
    if (found) return 'Theme: $themeName. Secret word found: $secretWord.';
    final base = 'Theme: $themeName. Secret word, ${secretWord.length} letters, not found yet';
    if (revealed.length >= secretWord.length) return '$base. It is $secretWord.';
    final hints = [
      if (revealed.contains(0)) 'first letter ${secretWord[0]}',
      if (revealed.contains(secretWord.length - 1)) 'last letter ${secretWord[secretWord.length - 1]}',
    ];
    return hints.isEmpty ? '$base.' : '$base, ${hints.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semantics,
      liveRegion: true,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: found ? WColors.tileGlow : WColors.card,
          border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('THEME', style: WText.label),
                    Text(themeName, style: WText.button.copyWith(fontSize: 18, color: WColors.ink)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: WSize.gap2),
            for (int i = 0; i < secretWord.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _SecretSlot(
                  key: ValueKey('secret-slot-$i'),
                  letter: revealed.contains(i) ? secretWord[i] : null,
                  found: found,
                ),
              ),
            if (found) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle, color: WColors.grass, size: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _SecretSlot extends StatelessWidget {
  const _SecretSlot({super.key, required this.letter, required this.found});

  final String? letter;
  final bool found;

  @override
  Widget build(BuildContext context) {
    const size = Size(28, 32);
    final letter = this.letter;
    if (letter == null) {
      return CustomPaint(painter: _DashedSlotPainter(), child: SizedBox.fromSize(size: size));
    }
    return Container(
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: found ? WColors.sun : const Color(0xFFD9CBB0),
        border: Border.all(color: found ? WColors.ink : WColors.muted, width: 1.5),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        letter,
        textScaler: TextScaler.noScaling,
        style: const TextStyle(fontFamily: WFonts.display, fontSize: 19, color: WColors.ink, height: 1.0),
      ),
    );
  }
}

class _DashedSlotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WColors.muted
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(7)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedSlotPainter oldDelegate) => false;
}
