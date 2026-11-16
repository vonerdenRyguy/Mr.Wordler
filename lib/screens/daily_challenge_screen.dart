import 'dart:math';

import 'package:namer_app/components/timer.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../daily/daily_challenge_controller.dart';
import '../daily/daily_challenge_data.dart';
import '../daily/daily_puzzle.dart';
import '../daily/daily_seed.dart';
import '../daily/daily_tier.dart';
import '../daily/share_card.dart';
import '../daily/word_of_the_day.dart';
import '../online/family_online_controller.dart';
import '../players/family_word.dart';
import '../players/players.dart';
import '../dictionary/definition_service.dart';
import '../dictionary/word_speaker.dart';
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../game/letter_tile.dart';
import '../settings/settings_controller.dart';
import '../settings/word_level.dart';
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
  const DailyChallengeScreen({super.key, @visibleForTesting this.today, @visibleForTesting this.level});

  // Overridable only for tests, so a test can pick the day's puzzle.
  final DateTime? today;
  // Null = the player's saved word level.
  final WordLevel? level;

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
    // The level is fixed for the round: changing it in Settings applies to
    // the next puzzle opened.
    _puzzle = dailyPuzzleFor(_today, widget.level ?? ref.read(settingsProvider).wordLevel);
    // ConsumerState's `ref` (unlike ProviderScope.containerOf(context)) is
    // safe to read in initState.
    _alreadyPlayed = ref.read(dailyChallengeProvider.notifier).hasPlayedToday(_today);
    if (!_alreadyPlayed) initSpellCheck();
  }

  @override
  Widget build(BuildContext context) {
    if (_alreadyPlayed) return const _AlreadyPlayedView();
    final secret = _puzzle.secretWord;
    final info = _puzzle.level.info;
    return ProviderScope(
      overrides: [
        gridConfigProvider.overrideWithValue(
          GridConfig(
            boardWidth: info.boardSize,
            boardHeight: info.boardSize,
            rackSize: info.letters,
            initialRack: _puzzle.letters,
          ),
        ),
        landingNoteProvider.overrideWithValue((word) => word.toUpperCase() == secret ? 'Secret word!' : null),
      ],
      child: _DailyChallengeBody(puzzle: _puzzle, today: _today),
    );
  }
}

/// What pressing Check does in a Daily round.
enum DailyCheck {
  /// Every word is real and joined up, and few enough letters are left.
  win,

  /// The words are fine, but more letters must be placed first (only at a
  /// level that allows leftovers, where "how many more" is worth saying).
  placeMore,

  /// Show the usual list of words found.
  notYet,
}

DailyCheck dailyCheckOutcome({required bool boardOk, required int lettersLeft, required int leftoverAllowed}) {
  if (!boardOk) return DailyCheck.notYet;
  if (lettersLeft <= leftoverAllowed) return DailyCheck.win;
  return leftoverAllowed > 0 ? DailyCheck.placeMore : DailyCheck.notYet;
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
  // The meaning clue had nothing to show (offline), so it gave a letter
  // instead (see _fallbackIndex).
  bool _fallbackShown = false;

  String get _secret => widget.puzzle.secretWord;
  WordLevelInfo get _info => widget.puzzle.level.info;

  // Sprout: one clue per letter of the hidden word.
  int get _maxClues => _info.unlimitedClues ? _secret.length : _info.clues.length;

  // The letter a meaning clue falls back to: the last one, or the third
  // where the level already has a last-letter clue.
  int get _fallbackIndex => _info.clues.contains(ClueKind.lastLetter) ? 2 : _secret.length - 1;

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
          levelName: _info.name,
        );
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // The meaning for the meaning clue, with the word itself hidden, or null
  // when there's nothing to show (offline, or no entry).
  Future<String?> _loadClueMeaning() async {
    final meaning = widget.puzzle.meaning ?? await ref.read(definitionServiceProvider).getDefinition(_secret);
    if (meaning == null || meaning.isEmpty) {
      if (mounted) setState(() => _fallbackShown = true);
      return null;
    }
    return hideWordInMeaning(meaning, _secret);
  }

  Future<void> _onClue() async {
    if (_roundEnded || _secretFound) return;
    final used = _cluesUsed;
    if (used >= _maxClues) return;

    if (_info.unlimitedClues) {
      // Sprout: each clue just shows the next letter in the strip.
      ref.read(dailyChallengeProvider.notifier).useClue(widget.today, max: _maxClues);
      HapticFeedback.selectionClick();
      setState(() {});
      return;
    }

    final kind = _info.clues[used];
    if (kind == ClueKind.wholeWord) {
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

    ref.read(dailyChallengeProvider.notifier).useClue(widget.today, max: _maxClues);
    setState(() {});
    final gotIt = [WordlerDialogAction('Got it', () {})];
    final fallback = _fallbackIndex == _secret.length - 1
        ? 'It ends with ${_secret[_fallbackIndex]}.'
        : 'The third letter is ${_secret[_fallbackIndex]}.';
    switch (kind) {
      case ClueKind.firstLetter:
        await showWordlerDialog<void>(
          context,
          title: 'First letter',
          bodyText: 'It starts with ${_secret[0]}.',
          actions: gotIt,
        );
      case ClueKind.lastLetter:
        await showWordlerDialog<void>(
          context,
          title: 'Last letter',
          bodyText: 'It ends with ${_secret[_secret.length - 1]}.',
          actions: gotIt,
        );
      case ClueKind.secondLetter:
        await showWordlerDialog<void>(
          context,
          title: 'Second letter',
          bodyText: 'The second letter is ${_secret[1]}.',
          actions: gotIt,
        );
      case ClueKind.meaning:
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
              return Text(snapshot.data ?? fallback, style: WText.body);
            },
          ),
          actions: gotIt,
        );
      case ClueKind.wholeWord:
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

    final lettersLeft = ref.read(gridGameControllerProvider).rackCells.where((c) => c != null).length;
    final allowed = _info.leftoverAllowed;
    final outcome = dailyCheckOutcome(
      boardOk: result.areValid && result.areConnected,
      lettersLeft: lettersLeft,
      leftoverAllowed: allowed,
    );
    if (outcome == DailyCheck.placeMore) {
      // Explorer: good words so far, just not enough letters placed yet.
      final more = lettersLeft - allowed;
      showWordlerDialog<void>(
        context,
        title: 'Good words!',
        bodyText: 'Place $more more letter${more == 1 ? '' : 's'} to finish.',
        actions: [WordlerDialogAction('OK', () {})],
      );
      return;
    }
    if (outcome == DailyCheck.notYet) {
      showCheckResultDialog(context, result);
      return;
    }
    _finish(secretFound: result.words.map((w) => w.toUpperCase()).contains(_secret));
  }

  // The round is won: save it, pay out, and show the result.
  void _finish({required bool secretFound}) {
    if (_roundEnded) return;
    _roundEnded = true;
    _stopwatchManager.stop();
    final timeSeconds = _elapsedSeconds;
    final cluesUsed = _cluesUsed;
    final tier = tierForDailyResult(
      completed: true,
      time: Duration(seconds: timeSeconds),
      bonusWordFound: secretFound,
    );
    final coins = secretFound ? secretWordCoins(cluesUsed, unlimitedClues: _info.unlimitedClues) : 0;

    ref.read(dailyChallengeProvider.notifier).recordAttempt(
          now: widget.today,
          completed: true,
          timeSeconds: timeSeconds,
          bonusWordFound: secretFound,
          tierAwarded: tier,
          themeName: widget.puzzle.theme.name,
          secretWord: _secret,
          cluesUsed: cluesUsed,
          levelName: _info.name,
        );

    // With a family on this phone, a finished Daily uncovers this player's
    // share of today's family word (spec-07).
    // In an online family, it uncovers their share of the online family's
    // word instead (spec-09).
    final players = ref.read(playersProvider);
    final familyWords = ref.read(wordsOfTheDayProvider).valueOrNull;
    final online = ref.read(familyOnlineProvider);
    if (online.stage == OnlineStage.member && familyWords != null && familyWords.isNotEmpty) {
      ref.read(familyOnlineProvider.notifier).recordPlayed(
            now: widget.today,
            word: familyWordFor(widget.today, familyWords).word,
          );
    } else if (players.isFamily && familyWords != null && familyWords.isNotEmpty) {
      ref.read(familyWordProvider.notifier).recordPlayed(
        playerId: players.currentId,
        now: widget.today,
        word: familyWordFor(widget.today, familyWords).word,
        playerIds: [for (final p in players.players) p.id],
      );
    }

    // With a family online, everyone sees this player has played today
    // (spec-08). Does nothing when this player isn't in one.
    ref.read(familyOnlineProvider.notifier).markPlayed(widget.today);

    final portfolioController = ref.read(portfolioProvider.notifier);
    final portfolioData = ref.read(portfolioProvider);
    awardDailyTileToPortfolio(portfolioController, portfolioData, tier);
    portfolioController.addXp(secretFound ? 150 : 100);
    if (coins > 0) portfolioController.addCurrency(coins);

    if (!mounted) return;
    if (_info.finishOnSecretWord) {
      _showSproutResult(coins);
      return;
    }
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

  // The Sprout result: the word in big tiles, what it means, and a button
  // to hear it. The learning moment, so there is nothing else on it.
  void _showSproutResult(int coins) {
    final speaker = ref.read(wordSpeakerProvider);
    final meaning = widget.puzzle.meaning;
    showWordlerDialog<void>(
      context,
      title: 'You found it!',
      barrierDismissible: false,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: _secret,
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final l in _secret.split(''))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: SizedBox(width: 52, height: 52, child: LetterTile(letter: l, faceColor: WColors.sun)),
                    ),
                ],
              ),
            ),
          ),
          if (meaning != null) ...[
            const SizedBox(height: WSize.gap3),
            const Text('WHAT IT MEANS', style: WText.label, textAlign: TextAlign.center),
            Text(meaning, style: WText.body.copyWith(fontSize: 18), textAlign: TextAlign.center),
          ],
          const SizedBox(height: WSize.gap3),
          ChunkyButton(
            label: 'Hear the word',
            icon: Icons.volume_up,
            kind: ChunkyKind.secondary,
            expand: true,
            onPressed: () => speaker.speak(_secret),
          ),
          const SizedBox(height: WSize.gap3),
          Text('+$coins coins', style: WText.bodyBold.copyWith(color: WColors.grass), textAlign: TextAlign.center),
        ],
      ),
      actions: [
        WordlerDialogAction('Done', () => Navigator.of(context).popUntil((route) => route.isFirst)),
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

    final info = _info;
    final size = info.boardSize;
    ref.listen<List<String?>>(gridGameControllerProvider.select((s) => s.boardCells), (prev, next) {
      if (_secretFound || !boardContainsWord(next, size, size, _secret)) return;
      setState(() => _secretFound = true);
      if (info.finishOnSecretWord) {
        // Sprout: that's the whole puzzle. A short pause lets the word
        // glow on the board first.
        Future<void>.delayed(const Duration(milliseconds: 900), () {
          if (mounted) _finish(secretFound: true);
        });
      }
    });

    final used = min(cluesUsed, _maxClues);
    final all = [for (int i = 0; i < _secret.length; i++) i];
    final revealed = <int>{
      if (_secretFound) ...all,
      if (info.unlimitedClues)
        for (int i = 0; i < used; i++) i,
      for (int i = 0; i < used && !info.unlimitedClues; i++)
        ...switch (info.clues[i]) {
          ClueKind.firstLetter => [0],
          ClueKind.lastLetter => [_secret.length - 1],
          ClueKind.secondLetter => [1],
          ClueKind.meaning => [if (_fallbackShown) _fallbackIndex],
          ClueKind.wholeWord => all,
        },
    };
    final cluesLeft = _maxClues - used;
    final clueStatus = _secretFound
        ? 'Found'
        : cluesLeft == 0
            ? 'No more'
            : (info.unlimitedClues ? 'Next letter' : '$cluesLeft left');

    // The back gesture asks first, the same as the Leave button.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: GameLayout(
        onLeave: _confirmLeave,
        // No clock on screen at Sprout and Explorer; the time is still saved.
        pill: info.showClock
            ? GamePill(label: 'Time', value: _stopwatchManager.elapsedTime, color: WModeColors.daily)
            : GamePill(label: '', value: info.name, color: info.color),
        showLettersLeft: !info.finishOnSecretWord,
        // Sprout has clues without limit, so nothing to give up on.
        giveUp: info.finishOnSecretWord ? null : _giveUp,
        onCheck: _onCheckPressed,
        showCheck: !info.finishOnSecretWord,
        rackColumns: switch (info.letters) { <= 8 => 4, <= 12 => 6, <= 16 => 8, _ => 7 },
        rackWidthFactor: info.letters <= 8 ? 0.75 : 1.0,
        header: SecretWordStrip(
          themeName: widget.puzzle.theme.name,
          secretWord: _secret,
          revealed: revealed,
          found: _secretFound,
        ),
        leading: ClueButton(
          status: clueStatus,
          onPressed: (_secretFound || cluesLeft == 0) ? null : _onClue,
        ),
        actionHint: info.finishOnSecretWord
            ? 'Spell the hidden word to finish.'
            : info.leftoverAllowed > 0
                ? 'You can finish with ${info.leftoverAllowed} letters left over.'
                : 'Find the secret word for a bonus.',
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
