
import 'dart:convert';

import 'package:namer_app/components/timer.dart';
import '../components/valid_word_check.dart' show initSpellCheck;
import '../game/grid_board_widget.dart';
import '../game/grid_config.dart';
import '../game/grid_providers.dart';
import '../game/tile_location.dart';

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

  // Timestamp of the last back-swipe/back-button attempt, used to
  // implement "press back twice within 2 seconds to exit".
  DateTime? _lastPopAttempt;

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

  @override
  Widget build(BuildContext context) {
    // PopScope intercepts the Android back gesture/button so we can
    // require a second swipe/press within 2 seconds before actually exiting.
    // canPop stays false always: we decide fresh on every attempt below,
    // rather than trying to flip canPop and pop in the same callback (that
    // races PopScope's internal state, which only updates on the *next*
    // rebuild, so the immediate pop attempt sees the stale "blocked" value
    // and silently does nothing).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final now = DateTime.now();
        if (_lastPopAttempt != null &&
            now.difference(_lastPopAttempt!) < const Duration(seconds: 2)) {
          // Second swipe within 2 seconds: pop directly. Navigator.pop is
          // an unconditional, imperative pop -- unlike maybePop, it does
          // not consult PopScope's canPop, so it isn't blocked here.
          _stopwatchManager.stop();
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
      child:  Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          toolbarHeight: 90,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // "Trade in" drop zone: drag a rack tile here to swap it
              // for 3 fresh letters drawn from the pool.
              DragTarget<TileLocation>(
                builder: (context, candidateData, rejectData) {
                  return  Container(
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Image.asset(
                      'lib_assests/trade.png',
                      height: kToolbarHeight - 5,
                    ),
                  );
                },
                onWillAcceptWithDetails: (details) {
                  if (details.data.zone != TileZone.rack) return false;
                  // Only allow a trade-in if the rack has more than 2
                  // open slots (once this tile leaves too), since a trade
                  // removes 1 tile and adds 3.
                  final rack = ref.read(gridGameControllerProvider).rackCells;
                  final emptyCount = rack
                      .asMap()
                      .entries
                      .where((e) => e.value == null || e.key == details.data.index)
                      .length;
                  if (emptyCount < 3) {
                    showDialog(
                      context: context,
                      builder: (context) => const AlertDialog(
                        title: Text("Must have 3 open slots"),
                      ),
                    );
                    return false;
                  }
                  return true;
                },
                onAcceptWithDetails: (DragTargetDetails<TileLocation> details) {
                  ref.read(gridGameControllerProvider.notifier).tradeIn(details.data.index);
                },
              ),
              // "Check" button: validates the current board state and
              // shows the appropriate result dialog (win / invalid words /
              // disconnected words).
              ElevatedButton(
                onPressed: () async {
                  final controller = ref.read(gridGameControllerProvider.notifier);
                  // Scan the board for words (rows + columns), check them
                  // against the dictionary, and check word connectivity.
                  var result = await controller.checkWords();
                  // The word check is async; bail out if the player left
                  // this screen while it was running.
                  if (!context.mounted) return;
                  Widget dialog = buildWordListDialog(result.words, result.areValid);
                  Widget notConnectedDialog = unconnectedDialog();

                  // Win condition: every letter the player has been dealt
                  // is placed on the board. Read state fresh (post-await)
                  // in case a tile moved while the check was running.
                  bool isWin = ref.read(gridGameControllerProvider).isPoolEmptied;
                  if (isWin && result.areValid && result.areConnected) {
                    // All letters placed, all words valid, all connected -> win.
                    _stopwatchManager.stop();
                    String finalTime = _stopwatchManager.getElapsedTime();
                    showDialog(
                      context: context,
                      builder: (context) => winDialog(finalTime, result.words),
                    );
                  } else if (!result.areConnected && result.areValid){
                    // Words are valid individually but not all touching.
                    showDialog(
                      context: context,
                      builder: (context) => notConnectedDialog,
                    );
                  } else {
                    // Otherwise show the list of words with valid/invalid styling.
                    showDialog(
                      context: context,
                      builder: (context) => dialog,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.green,
                ),
                child: const Text('Check'),
              ),
              // Elapsed-time display, kept in sync by _stopwatchManager.
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent,
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  _stopwatchManager.elapsedTime,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.deepPurple,
          automaticallyImplyLeading: false, // Remove back arrow
        ),
        body: const SafeArea(
            child: Column(
              children: [
                // Top section: the board where words are formed.
                Expanded(flex: 5, child: GridBoardView()),
                // Middle section: the player's letter rack.
                Expanded(flex: 3, child: GridRackView()),
                // Bottom decorative filler strip.
                Expanded(
                  flex: 1,
                  child: ColoredBox(color: Colors.orangeAccent),
                ),
              ],
            ),
        ),
      ),
    );
  }

  // Dialog listing the words found on the board, styled green if they're
  // all valid dictionary words or red if any are invalid.
  Widget buildWordListDialog(List<String> words, bool areWordsValid) {
    return AlertDialog(
      backgroundColor: Colors.orangeAccent,
      title: Text(areWordsValid ? 'Valid Words!' : 'Invalid Words:'),
      content: Column(mainAxisSize: MainAxisSize.min,
        children: words.map((word) => Text(word, style: TextStyle(
          fontWeight: FontWeight.bold,
          color: areWordsValid ? Colors.green : Colors.red,
        ))).toList(),
      ),
    );
  }

  // Win dialog shown when the player successfully places all their
  // letters into valid, connected words. Plays a confetti animation and
  // lets the player submit their name/time to the local leaderboard
  // (persisted via SharedPreferences).
  Widget winDialog(String winningTime, List<String> winningWords) {
    final nameController = TextEditingController();
    late ConfettiController confettiController;

    return StatefulBuilder(
      builder: (context, setState) {
        confettiController =
            ConfettiController(duration: const Duration(seconds: 6));
        confettiController.play();

        return AlertDialog(
          backgroundColor: Colors.orangeAccent,
          title: const Text("You Win!"),
          content: Stack(
            children: [
              SingleChildScrollView( // Wrap content in SingleChildScrollView
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Your Time: $winningTime"),
                    const SizedBox(height: 10),
                    const Text("Winning Words:"),
                    ...winningWords.map((word) => Text("- $word")).toList(),
                    const SizedBox(height: 10.0),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                          hintText: 'Enter your name'),
                    ),
                  ],
                ),
              ),
              // Confetti burst overlaid on top of the dialog content.
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: confettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                String playerName = nameController.text;
                if (playerName.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();

                  // Load existing leaderboard entries (stored as JSON strings).
                  List<String> entries = prefs.getStringList('leaderboardEntries') ?? [];

                  // Decode stored entries into a list of maps
                  List<Map<String, dynamic>> leaderboard = entries.map((e) {
                    return Map<String, dynamic>.from(
                        jsonDecode(e) as Map<String, dynamic>
                    );
                  }).toList();

                  // Converts a "MM:SS" display string into total seconds so
                  // entries can be sorted numerically.
                  int parseTimeToSeconds(String time) {
                    final parts = time.split(":");
                    if (parts.length == 2) {
                      int minutes = int.tryParse(parts[0]) ?? 0;
                      int seconds = int.tryParse(parts[1]) ?? 0;
                      return minutes * 60 + seconds;
                    }
                    return 0;
                  }


                  // Add new entry
                  leaderboard.add({
                    "name": playerName,
                    "time": parseTimeToSeconds(winningTime),
                    "displayTime": winningTime,
                  });

                  // Sort by time (ascending = lowest first)
                  leaderboard.sort((a, b) => (a["time"] as int).compareTo(b["time"] as int));

                  // Keep only top 100
                  if (leaderboard.length > 100) {
                    leaderboard = leaderboard.sublist(0, 100);
                  }

                  // Save back as JSON strings
                  List<String> encoded =
                  leaderboard.map((e) => jsonEncode(e)).toList();
                  await prefs.setStringList('leaderboardEntries', encoded);
                }

                // Bail out if the dialog's context is gone after the awaits above.
                if (!context.mounted) return;
                // Return to the very first route (the menu screen).
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text("Submit"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  // Dialog shown when valid words exist on the board but they don't all
  // connect into a single group (a Bananagrams rule violation).
  Widget unconnectedDialog() {
    return const AlertDialog(
      backgroundColor: Colors.orangeAccent,
      title: Text('All valid words must be connected'),
      content: Column(mainAxisSize: MainAxisSize.min),
    );
  }
}
