import 'dart:async';

import 'package:flutter/services.dart';
import 'package:spell_check_on_client/spell_check_on_client.dart';

/*
This file will go column by column checking if there is a letter.
If there is a letter add that letter to a string then continue to check the next tile
if there is a letter add that one to the string until you hit another null tile
then check to see if that word is changed after spell check is done
If it isn't add it to an array. There will be also be a check for one letter words
If there is a one letter word it wont go through the checker but will skip it and move on

Then it repeats it for the rows

 */

// DIFFICULTY: HARD
// ATTEMPTING TO ADD CHECK F0R IF ALL WORDS ARE CONNECTED
late SpellCheck spellCheck;
Map<String, Set<int>> wordPositionsMap = {};

Future<void> initSpellCheck() async {
  String language = 'en';
  String content = await rootBundle.loadString('lib_assests/words.txt');
  spellCheck = SpellCheck.fromWordsContent(content,
      letters: LanguageLetters.getLanguageForLanguage(language));
}
Future<bool> isValidWord(String word) async {
  //await initSpellCheck();

  final suggestions = spellCheck.didYouMean(word.toLowerCase());
  return suggestions.isEmpty;
}

// Function to check words in a column and return their positions
Future<({Iterable<Set<int>> positions, List<String> words})>
checkColumnWithPositions(
    List<String?> letterPositions, int columnIndex, int gridSize) async {
  List<String> validWords = [];
  List<String> notValid = [];
  List<Set<int>> positions = []; // To store positions of letters in valid words
  String currentWord = "";
  Set<int> currentWordPositions = {};

  for (int rowIndex = 0; rowIndex < gridSize; rowIndex++) {
    int index = rowIndex * gridSize + columnIndex;
    String? letter = letterPositions[index];

    if (index < 100) {
      if (letter != null) {
        currentWord += letter;
        currentWordPositions.add(index); // Add index to current word positions
      } else {
        if (currentWord.length > 1) {
          if (await isValidWord(currentWord)) {
            validWords.add(currentWord);
            positions.add(currentWordPositions.toSet()); // Store positions
            wordPositionsMap[currentWord] = currentWordPositions.toSet();
          } else {
            notValid.add(currentWord);
          }
        }
        currentWord = "";
        currentWordPositions = {}; // Reset for next word
      }
    }
  }

  // Check the last word in the column
  if (currentWord.length > 1 && await isValidWord(currentWord)) {
    validWords.add(currentWord);
    positions.add(currentWordPositions.toSet());
  }

  if (notValid.isEmpty) {
    print("Column Valid: $validWords");
    return (words: validWords, positions: positions);
  } else {
    print("Column invalid: $notValid");
    return (words: notValid, positions: <Set<int>>[].toSet()); // Return empty positions for invalid words
  }
}

// Function to check words in a row and return their positions
Future<({Iterable<Set<int>> positions, List<String> words})>
checkRowWithPositions(
    List<String?> letterPositions, int rowIndex, int gridSize) async {
  List<String> validWords = [];
  List<String> notValid = [];
  List<Set<int>> positions = [];
  String currentWord = "";
  Set<int> currentWordPositions = {};

  for (int columnIndex = 0; columnIndex < gridSize; columnIndex++) {
    int index = rowIndex * gridSize + columnIndex;
    String? letter = letterPositions[index];

    if (index < 100) {
      if (letter != null) {
        currentWord += letter;
        currentWordPositions.add(index);
      } else {
        if (currentWord.length > 1) {
          if (await isValidWord(currentWord)) {
            validWords.add(currentWord);
            positions.add(currentWordPositions.toSet());
            wordPositionsMap[currentWord] = currentWordPositions.toSet();
          } else {
            notValid.add(currentWord);
          }
        }
        currentWord = "";
        currentWordPositions = {};
      }
    }
  }

  // Check the last word in the row (if any)
  if (currentWord.length > 1 && currentWord.length < 100 && await isValidWord(currentWord)) {
    validWords.add(currentWord);
    positions.add(currentWordPositions.toSet());
  }

  if (notValid.isEmpty) {
    print("Row Valid: $validWords");
    return (words: validWords, positions: positions);
  } else {
    print("Row invalid: $notValid");
    return (words: notValid, positions: <Set<int>>[].toSet());
  }
}



// Main function to find all valid words in the grid
Future<({List<String> words, bool areValid, bool areConnected})>
findValidWords(List<String?> letterPositions, int gridSize) async {
  await initSpellCheck();
  List<String> allValidWords = [];
  List<String> allInvalidWords = [];
  List<Set<int>> wordTilePositions = [];

  // Check columns
  for (int columnIndex = 0;
  columnIndex < gridSize && columnIndex * gridSize < 100;
  columnIndex++) {
    var result =
    await checkColumnWithPositions(letterPositions, columnIndex, gridSize);
    if (result.words.isNotEmpty && await isValidWord(result.words.first)) {
      allValidWords.addAll(result.words);
      wordTilePositions.addAll(result.positions);
    } else {
      allInvalidWords.addAll(result.words);
    }
  }

  // Check rows
  for (int rowIndex = 0;
  rowIndex < gridSize && rowIndex * gridSize < 100;
  rowIndex++) {
    var result =
    await checkRowWithPositions(letterPositions, rowIndex, gridSize);
    if (result.words.isNotEmpty && await isValidWord(result.words.first)) {
      allValidWords.addAll(result.words);
      wordTilePositions.addAll(result.positions);
    } else {
      allInvalidWords.addAll(result.words);
    }
  }

  // Check if all words are connected
  bool areConnected = true;
  //String unconnectedWord = "";
  if (wordTilePositions.length > 1) {
    for (int i = 0; i < wordTilePositions.length; i++) {
      bool isConnected = false;

      // Check if the current word overlaps with ANY other word
      for (int j = 0; j < wordTilePositions.length; j++) {
        if (i != j && wordTilePositions[i].intersection(wordTilePositions[j]).isNotEmpty) {
          isConnected = true;
          break; // No need to check further for this word
        }
      }

      if (!isConnected) {
        areConnected = false;
        String unconnectedWord = findWordFromPositions(wordTilePositions[i]);
        print("Unconnected word: $unconnectedWord");
        break;
      }
    }
  }

  print("Valid words: $allValidWords");
  print("Invalid words: $allInvalidWords");
  print("Are words connected: $areConnected");

  // Return the result
  return (
  words: allInvalidWords.isEmpty ? allValidWords : allInvalidWords,
  areValid: allInvalidWords.isEmpty,
  areConnected: areConnected
  );
}

String findWordFromPositions(Set<int> positions) {
  for (var entry in wordPositionsMap.entries) {
    if (entry.value.toSet() == positions) {
      return entry.key;
    }
  }
  return ""; // Or handle the case where the word is not found
}
