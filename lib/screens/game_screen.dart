
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
  List<String> allLetters = [];
  List<String?> letterPositions = List.filled(121, null);
  List<GlobalKey> tileKeys = List.generate(121, (index) => GlobalKey());
  List<String> letters = [];
  late StopwatchManager _stopwatchManager;
  DateTime? _lastPopAttempt;

  @override
  void initState() {
    super.initState();
    _stopwatchManager = StopwatchManager(context);
    _stopwatchManager.start();
    initSpellCheck();
    letters = LetterGenerator.generateLetters(144);
    for (int i = 0; i < 21; i++) {
      letterPositions[100 + i] = letters[i];
    }
    for (int i = 0; i < 21; i++) {
      letters.remove(i);
      allLetters.add(letters[i]);
    }
  }
  @override
  Widget build(BuildContext context) {
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
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DragTarget<GlobalKey>(
                builder: (context, candidateData, rejectData) {
                  return Image.asset(
                    'lib_assests/trade.png',
                    height: kToolbarHeight - 5,
                  );
                },
                onWillAcceptWithDetails: (data) {
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
                    final GlobalKey draggedTileKey = details.data;
                    int previousIndex = -1;
                    for (int i = 0; i < tileKeys.length; i++) {
                      if (tileKeys[i] == draggedTileKey) {
                        previousIndex = i;
                        break;
                      }
                    }
                    if (previousIndex != -1) {
                      String? draggedLetter = letterPositions[previousIndex];
                       if (draggedLetter != null) {
                         letterPositions[previousIndex] = null;
                         allLetters.remove(draggedLetter);
                         letters.add(draggedLetter);
                       }
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
              ElevatedButton(
                onPressed: () async {
                  var result = await findValidWords(letterPositions, 10);
                  Widget dialog = buildWordListDialog(result.words,
                      result.areValid);
                  Widget notConnectedDialog = unconnectedDialog();

                  int takenSpots = 0;
                  for (int i = 0; i < 100; i++) {
                    if (letterPositions[i] != null) {
                      takenSpots++;
                    }
                  }
                  bool isWin = takenSpots == allLetters.length;
                  // Must handle this problem with repeated letters
                  //print("isWin: $isWin");
                  print(takenSpots);
                  print(allLetters);
                  print("Valid words letters: ${result.words.join().replaceAll(RegExp(r'[^a-zA-Z]'), '')}");
                  if (isWin && result.areValid && result.areConnected) {
                    _stopwatchManager.stop();
                    String finalTime = _stopwatchManager.getElapsedTime();
                    showDialog(
                      context: context,
                      builder: (context) => winDialog(finalTime, result.words),
                    );
                  } else if (!result.areConnected && result.areValid){
                    showDialog(
                      context: context,
                      builder: (context) => notConnectedDialog,
                    );
                  } else {
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
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white), // Customize border
                  borderRadius: BorderRadius.circular(8.0), // Customize border radius
                ),
                child: Text(_stopwatchManager.elapsedTime),
              ),
            ],
          ),
          backgroundColor: Colors.deepPurple,
          automaticallyImplyLeading: false, // Remove back arrow
        ),
        body: Column(
          children: [
            InteractiveViewer(
              boundaryMargin: EdgeInsets.all(0.0),
              minScale: 0.4, // Minimum zoom level
              maxScale: 2.5, // Maximum zoom level
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.47,
                child: GridView.count(
                  crossAxisCount: 10,
                  physics: NeverScrollableScrollPhysics(),
                  children: List.generate(100, (index) {
                    return buildDragTarget(index);
                  }),
                ),
              ),
            ),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.3,
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
                    //childAspectRatio: 1,
                    childAspectRatio: 0.7,
                    shrinkWrap: true, // Important for centering
                    children: List.generate(21, (index) {
                      return buildDragTarget(100 + index);
                    }),
                  ),
                ),
              ),
            ),
            Container(
              height: MediaQuery.of(context).size.height * 0.1275,
              color: Colors.orangeAccent,
            ),
          ],
        ),
      ),
    );
  }
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
                child: letterPositions[index] != null
                    ? Draggable<GlobalKey>(
                  data: tileKeys[index],
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
                  childWhenDragging: Container(
                    padding: const EdgeInsets.all(3.0),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
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

  Widget buildWordListDialog(List<String> words, bool areWordsValid) {
    return AlertDialog(
      title: Text(areWordsValid ? 'Valid Words!' : 'Invalid Words:'),
      content: Column(mainAxisSize: MainAxisSize.min,
        children: words.map((word) => Text(word, style: TextStyle(
          color: areWordsValid ? Colors.green : Colors.red,
        ))).toList(),
      ),
    );
  }

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

                  List<String> entries = prefs.getStringList(
                      'leaderboardEntries') ?? [];

                  // Limit the list to 100 entries
                  if (entries.length >= 100) {
                    entries.removeAt(0); // Remove the oldest entry
                  }

                  final newEntry = '$playerName - $winningTime';
                  entries.add(newEntry);
                  await prefs.setStringList('leaderboardEntries', entries);
                }
                Navigator.of(context).popUntil((route) =>
                route.isFirst); // Close the dialog
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

  Widget unconnectedDialog() {
    return AlertDialog(
      title: Text('All valid words must be connected'),
      content: Column(mainAxisSize: MainAxisSize.min,
      ),
    );
  }
}