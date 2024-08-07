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

// DIFFICULT: HARD
// ATTEMPTING TO ADD CHECK F0R IF ALL WORDS ARE CONNECTED
late SpellCheck spellCheck;

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

// Function to check words in a column
Future<List<String>> checkColumn(List<String?> letterPositions, int columnIndex,
    int gridSize) async {
  List<String> validWords = [];
  List<String>notValid =[];
  String currentWord = "";

  for (int rowIndex = 0; rowIndex < gridSize; rowIndex++) {
    int index = rowIndex * gridSize + columnIndex;
    String? letter = letterPositions[index];

    if (index < 100) {
      String? letter = letterPositions[index];

      if (letter != null) {
        currentWord += letter;
      } else {
        if (currentWord.length > 1) {
          if (await isValidWord(currentWord)) {
            validWords.add(currentWord);
          } else {
            notValid.add(currentWord);
          }
        }
        currentWord = "";
      }
    }
  }

  // Check the last word in the column (if any)
  if (currentWord.length > 1 && await isValidWord(currentWord)) {
    validWords.add(currentWord);
  }

  if (notValid.isEmpty) {
    print("Column Valid: $validWords");
    return validWords;
  } else {
    print("Column invalid: $notValid");
    return notValid;
  }
}

// Function to check words in a row
Future<List<String>> checkRow(List<String?> letterPositions, int rowIndex,
    int gridSize) async {
  List<String> validWords = [];
  List<String>notValid =[];
  String currentWord = "";

  for (int columnIndex = 0; columnIndex < gridSize; columnIndex++) {
    int index = rowIndex * gridSize + columnIndex;
    String? letter = letterPositions[index];

    if (index < 100) {
      String? letter = letterPositions[index];

      if (letter != null) {
        currentWord += letter;
      } else {
        if (currentWord.length > 1) {
          if (await isValidWord(currentWord)) {
            validWords.add(currentWord);
          } else {
            notValid.add(currentWord);
          }
        }
        currentWord = "";
      }
    }
  }

  // Check the last word in the row (if any)
  if (currentWord.length > 1 && currentWord.length < 100 && await isValidWord(currentWord)) {
    validWords.add(currentWord);
  }

  if (notValid.isEmpty) {
    print("Row Valid: $validWords");
    return validWords;
  } else {
    print("Row invalid: $notValid");
    return notValid;
  }
}



// Main function to find all valid words in the grid
Future<({List<String> words, bool areValid})> findValidWords(List<String?> letterPositions, int gridSize) async {
  await initSpellCheck();
  List<String> allValidWords = [];
  List<String> allInvalidWords = [];

  // Check columns
  for (int columnIndex = 0; columnIndex < gridSize && columnIndex * gridSize < 100; columnIndex++) {
    List<String> columnResult = await checkColumn(letterPositions, columnIndex, gridSize);
    if (columnResult.isNotEmpty && await isValidWord(columnResult.first)) {
      allValidWords.addAll(columnResult);
    } else {
      allInvalidWords.addAll(columnResult);
    }
  }

  // Check rows
  for (int rowIndex = 0; rowIndex < gridSize && rowIndex * gridSize < 100; rowIndex++) {
    List<String> rowResult = await checkRow(letterPositions, rowIndex, gridSize);
    if (rowResult.isNotEmpty && await isValidWord(rowResult.first)) {
      allValidWords.addAll(rowResult);
    } else {
      allInvalidWords.addAll(rowResult);
    }
  }

  print("Valid words: $allValidWords");
  print("invalid words: $allInvalidWords");
  //print(allInvalidWords.isEmpty);

  // Return correct list
  if (allInvalidWords.isEmpty) {
    return (words: allValidWords, areValid: true);
  } else {
    return (words: allInvalidWords, areValid: false);
  }
}
