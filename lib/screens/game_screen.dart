
import 'package:flutter/material.dart';
import 'package:namer_app/components/timer.dart';

import '../components/bananagramsTiles.dart';
import '../components/valid_word_check.dart';

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
    return Scaffold(
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
                    List<String> newLetters = [];
                    for (int i = 0; i < 3 && letters.isNotEmpty; i++) {
                      letters.shuffle();
                      newLetters.add(letters.removeLast());
                    }
                    allLetters.addAll(newLetters);
                    distributeLetters(newLetters);
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
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: GridView.count(
              crossAxisCount: 10,
              children: List.generate(100, (index) {
                return buildDragTarget(index);
              }),
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
              child: GridView.count(
                crossAxisCount: 7,
                childAspectRatio: 1.0,
                mainAxisSpacing: 8.0,
                crossAxisSpacing: 8.0,
                children: List.generate(21, (index) {
                  return buildDragTarget(100 + index);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget buildDragTarget(int index) {
    final isTopGrid = index < 100;
    return Padding(
      padding: EdgeInsets.all(isTopGrid ? 0.0 : 8.0),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: DragTarget<GlobalKey>(
          key:  tileKeys[index],
          builder: (context, candidateData, rejectedData) {
            return Container(
              decoration: BoxDecoration(
                color: candidateData.isNotEmpty
                    ? Colors.blue[100] // Highlight when hovering
                    : (isTopGrid ? Colors.amber[50] : Colors.grey[200]),
                border: Border.all(
                  color: isTopGrid ? Colors.black : Colors.grey,
                  width: 1.0,
                ),
                borderRadius: isTopGrid ? BorderRadius.circular(0.0)
                  : BorderRadius.circular(8.0),
              ),
              child: Center(
                child: letterPositions[index] != null
                    ? Draggable<GlobalKey>(
                  data: tileKeys[index],
                  feedback: Material(
                    child: Container(
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Colors.amber[100],
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Text(
                        letterPositions[index]!,
                        style: const TextStyle(fontSize: 20),
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
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Center(
                      child: Text(
                        letterPositions[index]!,
                        style: const TextStyle(fontSize: 20),
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
          // onLeave: (data) {
          // },
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
    return AlertDialog(
      title: Text("You Win!"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Your Time: $winningTime"),
          SizedBox(height: 10),
          Text("Winning Words:"),
          ...winningWords.map((word) => Text("- $word")).toList(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Close"),
        ),
      ],
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