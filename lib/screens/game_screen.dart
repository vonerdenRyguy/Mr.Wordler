
import 'dart:convert';

import 'package:namer_app/components/timer.dart';
import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // All letters currently "in play" for the player (board + rack combined).
  List<String> allLetters = [];

  // Flat representation of every tile slot in the game.
  // Indices 0-99   -> the 10x10 board grid.
  // Indices 100-120 -> the 21-slot letter rack (the player's hand).
  // A null entry means that slot is empty.
  List<String?> letterPositions = List.filled(121, null);

  // One GlobalKey per slot so DragTarget/Draggable widgets can identify
  // which slot a tile came from/is going to during drag-and-drop.
  List<GlobalKey> tileKeys = List.generate(121, (index) => GlobalKey());

  // The remaining "pool" of letters not yet dealt to the player
  // (used when trading in / drawing new tiles).
  List<String> letters = [];

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
    initSpellCheck(); // Load the dictionary used for word validation.

    // Generate the full Bananagrams-style letter pool (144 tiles).
    letters = LetterGenerator.generateLetters(144);

    // Deal the first 21 letters into the rack slots (100-120).
    for (int i = 0; i < 21; i++) {
      letterPositions[100 + i] = letters[i];
    }
    // NOTE: `letters.remove(i)` below removes by VALUE, not by index
    // (List.remove takes an Object, and `i` gets treated as an int value
    // to remove, which is likely not the intended behavior for popping
    // dealt tiles out of the draw pool). This mirrors existing behavior
    // and has not been changed.
    for (int i = 0; i < 21; i++) {
      letters.remove(i);
      allLetters.add(letters[i]);
    }
  }
  @override
  Widget build(BuildContext context) {
    // WillPopScope intercepts the Android back gesture/button so we can
    // require a second swipe/press within 2 seconds before actually exiting.
    return WillPopScope(
      onWillPop: () async {
        final now = DateTime.now();
        if (_lastPopAttempt != null &&
            now.difference(_lastPopAttempt!) < const Duration(seconds: 2)) {
          return true; // Exit if second swipe within 2 seconds
        }
        _lastPopAttempt = now;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Swipe again to exit'),
            duration: Duration(seconds: 2),
          ),
        );

        return false; // Don't exit on the first swipe
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
              DragTarget<GlobalKey>(
                builder: (context, candidateData, rejectData) {
                  return  Container(
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      //border: Border.all(color: Colors.white),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Image.asset(
                      'lib_assests/trade.png',
                      height: kToolbarHeight - 5,
                    ),
                  );
                },
                onWillAcceptWithDetails: (data) {
                  // Only allow a trade-in if the rack has more than 2
                  // open slots, since a trade removes 1 tile and adds 3.
                  List<int> emptyIndices = [];
                  for (int i = 100; i < 121; i++) {
                    if (letterPositions[i] == null) {
                      emptyIndices.add(i);
                    }
                  }
                  if (emptyIndices.length <= 2) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text("Must have 3 open slots"),
                      ),
                    );
                    return false;
                  }
                  return true;
                },
                onAcceptWithDetails: (DragTargetDetails<GlobalKey> details) {
                  setState(() {
                    // Find which slot the dropped tile came from.
                    final GlobalKey draggedTileKey = details.data;
                    int previousIndex = -1;
                    for (int i = 0; i < tileKeys.length; i++) {
                      if (tileKeys[i] == draggedTileKey) {
                        previousIndex = i;
                        break;
                      }
                    }
                    if (previousIndex != -1) {
                      // Remove the traded letter from play and return it
                      // to the draw pool.
                      String? draggedLetter = letterPositions[previousIndex];
                       if (draggedLetter != null) {
                         letterPositions[previousIndex] = null;
                         allLetters.remove(draggedLetter);
                         letters.add(draggedLetter);
                       }
                      // Deal 3 replacement letters after the current frame
                      // finishes, so the removal above is reflected first.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        setState(() {
                          List<String> newLetters = [];
                          for (int i = 0; i < 3 && letters.isNotEmpty; i++) {
                            letters.shuffle();
                            newLetters.add(letters.removeLast());
                          }
                          allLetters.addAll(newLetters);
                          distributeLetters(newLetters);
                        });
                      });
                    }
                  });
                },
              ),
              // "Check" button: validates the current board state and
              // shows the appropriate result dialog (win / invalid words /
              // disconnected words).
              ElevatedButton(
                onPressed: () async {
                  // Scan the board for words (rows + columns), check them
                  // against the dictionary, and check word connectivity.
                  var result = await findValidWords(letterPositions, 10);
                  Widget dialog = buildWordListDialog(result.words,
                      result.areValid);
                  Widget notConnectedDialog = unconnectedDialog();

                  // Count how many board slots are filled.
                  int takenSpots = 0;
                  for (int i = 0; i < 100; i++) {
                    if (letterPositions[i] != null) {
                      takenSpots++;
                    }
                  }
                  // Win condition: every letter the player has been dealt
                  // is placed on the board.
                  bool isWin = takenSpots == allLetters.length;
                  // Must handle this problem with repeated letters
                  //print("isWin: $isWin");
                  print(takenSpots);
                  print(allLetters);
                  print("Valid words letters: ${result.words.join().replaceAll(RegExp(r'[^a-zA-Z]'), '')}");
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
        body: SafeArea(
            child: Column(
              children: [
                // Top section: the 10x10 game board where words are formed.
                Expanded(
                  flex: 5,
                  child: InteractiveViewer(
                    // Lets the player pinch-zoom/pan the board.
                    boundaryMargin: EdgeInsets.zero,
                    minScale: 0.4,
                    maxScale: 2.5,
                    child: Center(   // 👈 keeps it centered if taller than wide
                      child: AspectRatio(
                        aspectRatio: 1.0,  // 👈 force it to stay square
                        child: GridView.count(
                          crossAxisCount: 10,
                          physics: NeverScrollableScrollPhysics(),
                          // Board slots are indices 0-99.
                          children: List.generate(100, (index) {
                            return buildDragTarget(index);
                          }),
                        ),
                      ),
                    ),
                  ),
                ),

                // Middle section: the player's letter rack (21 tiles).
                Expanded(
                  flex: 3,
                  child: Container( // Wrap the bottom GridView with a Container
                    decoration: BoxDecoration(
                      border: Border.all( // Apply border to the Container
                        color: Colors.black,
                        width: 2.0,
                      ),
                    ),
                    child: Center( // Add Center widget here
                      child: GridView.count(
                        physics: NeverScrollableScrollPhysics(),
                        crossAxisCount: 7,
                        childAspectRatio: 0.7,
                        //: 0.7,
                        shrinkWrap: true, // Important for centering
                        // Rack slots are indices 100-120.
                        children: List.generate(21, (index) {
                          return buildDragTarget(100 + index);
                        }),
                      ),
                    ),
                  ),
                ),
                // Bottom decorative filler strip.
                Expanded(
                  flex: 1,
                  child: Container(color: Colors.orangeAccent),
                ),
              ],
            ),
        ),
      ),
    );
  }

  // Builds a single drag-and-drop tile slot for either the board
  // (index < 100) or the rack (index >= 100). Handles rendering the
  // letter (if any), the drag "feedback" preview, and accepting drops
  // from other slots.
  Widget buildDragTarget(int index) {
    final isTopGrid = index < 100;
    return Padding(
      padding: EdgeInsets.all(isTopGrid ? 0.0 : 4.0),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: DragTarget<GlobalKey>(
          key:  tileKeys[index],
          builder: (context, candidateData, rejectedData) {
            return Container(
              padding: EdgeInsets.zero,
              decoration: BoxDecoration(
                // Highlight the slot blue while a tile is being dragged over it.
                color: candidateData.isNotEmpty
                    ? Colors.blue[100] // Highlight when hovering
                    : (isTopGrid ? Colors.orangeAccent : Colors.deepPurple),
                border: Border.all(
                  color: isTopGrid ? Colors.black : Colors.grey,
                  width: 1.5,
                ),
                borderRadius: isTopGrid ? BorderRadius.circular(0.0)
                    : BorderRadius.circular(8.0),
              ),
              child: Center(
                // Only render a draggable letter tile if this slot is occupied;
                // otherwise leave it empty.
                child: letterPositions[index] != null
                    ? Draggable<GlobalKey>(
                  data: tileKeys[index],
                  // What's shown under the finger/cursor while dragging.
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple,
                        //border: Border.all(color: Colors.grey),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        letterPositions[index]!,
                        style: TextStyle(
                          fontFamily: "Open Sans",
                          fontWeight: FontWeight.w900,
                          fontSize: isTopGrid ? 12.0 : 15.0,
                        ),
                      ),
                    ),
                  ),
                  // What remains in the original slot while a drag is in progress.
                  childWhenDragging: Container(
                    padding: const EdgeInsets.all(3.0),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  // Normal (non-dragging) appearance of the tile.
                  child: Container(
                    padding: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Center(
                        child: Text(
                          letterPositions[index]!,
                          style: TextStyle(
                            fontFamily: "Open Sans",
                            fontWeight: FontWeight.w900,
                            fontSize: isTopGrid ? 15.0 : 15.0,
                          ),
                        ),
                    ),
                  ),
                  // Once the drop is accepted elsewhere, clear this slot.
                  onDragCompleted: () {
                    setState(() {
                      letterPositions[index] = null;
                    });
                  },
                )
                    : const SizedBox.shrink(),
              ),
            );
          },
          // prevents overlapping of letters
          onWillAcceptWithDetails: (data) {
            if (letterPositions[index] != null) {
              return false;
            }
            return true;
          },
          onAcceptWithDetails: (DragTargetDetails<GlobalKey> details) {
            setState(() {
              final GlobalKey draggedTileKey = details.data;
              int previousIndex = -1;
              for (int i = 0; i < tileKeys.length; i++) {
                if (tileKeys[i] == draggedTileKey) {
                  previousIndex = i;
                  break;
                }
              }
              int currentIndex = index;
              if (previousIndex != -1 && currentIndex != -1) {
                // Move the letter to the new position
                String? draggedLetter = letterPositions[previousIndex]; // Get the letter from the previous position
                letterPositions[currentIndex] = draggedLetter; // Set the letter in the new position
                letterPositions[previousIndex] = null; // Clear the previous position
              }
            });
          },
        ),
      ),
    );
  }

  // After a trade-in, places the newly drawn letters into the first
  // available empty rack slots (indices 100-120).
  void distributeLetters( List<String> newLetters) {
    List<int> emptyIndices = [];
    for (int i = 100; i < 121; i++) {
      if (letterPositions[i] == null) {
        emptyIndices.add(i);
      }
    }
    for (int i = 0; i < newLetters.length && i < emptyIndices.length; i++) {
      letterPositions[emptyIndices[i]] = newLetters[i];
    }
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
                    // Customize other properties as needed
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

                // Return to the very first route (the menu screen).
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: Text("Submit"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        );
      },
    );
  }

  // Dialog shown when valid words exist on the board but they don't all
  // connect into a single group (a Bananagrams rule violation).
  Widget unconnectedDialog() {
    return AlertDialog(
      backgroundColor: Colors.orangeAccent,
      title: Text('All valid words must be connected'),
      content: Column(mainAxisSize: MainAxisSize.min,
      ),
    );
  }
}
