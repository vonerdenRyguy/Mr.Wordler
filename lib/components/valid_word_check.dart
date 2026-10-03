import 'dart:async';

import 'package:flutter/services.dart';
import 'package:spell_check_on_client/spell_check_on_client.dart';

import '../game/word_runs.dart';

/*
This file goes column by column checking if there is a letter.
If there is a letter add that letter to a string then continue to check the next tile
if there is a letter add that one to the string until you hit another null tile
then check to see if that word is changed after spell check is done
If it isn't add it to an array. There will be also be a check for one letter words
If there is a one letter word it wont go through the checker but will skip it and move on

Then it repeats it for the rows
 */

// The dictionary is identical for every game in progress, so it's loaded
// once and shared; everything else here is per-WordValidator-instance so
// multiple simultaneous grids (e.g. across game modes) don't leak state
// into each other.
Future<SpellCheck>? _spellCheckFuture;

Future<SpellCheck> _loadSpellCheck() {
  return _spellCheckFuture ??= () async {
    String content = await rootBundle.loadString('lib_assests/words.txt');
    return SpellCheck.fromWordsContent(content,
        letters: LanguageLetters.getLanguageForLanguage('en'));
  }();
}

// Kept for backwards compatibility with any call site that just wants the
// dictionary warmed up ahead of time.
Future<void> initSpellCheck() => _loadSpellCheck();

class WordCheckResult {
  final List<String> words;
  final bool areValid;
  final bool areConnected;

  const WordCheckResult({
    required this.words,
    required this.areValid,
    required this.areConnected,
  });
}

// Scans a rectangular board (boardWidth x boardHeight, row-major, null =
// empty) for words in rows/columns, checks them against the dictionary,
// and checks that all found words are connected into a single group.
// Instance-scoped (not global) so several boards (e.g. across game modes,
// or a fresh game vs. a previous one) never share state.
class WordValidator {
  final Map<String, Set<int>> _wordPositionsMap = {};

  Future<bool> isValidWord(String word) async {
    final spellCheck = await _loadSpellCheck();
    final suggestions = spellCheck.didYouMean(word.toLowerCase());
    return suggestions.isEmpty;
  }

  Future<({Iterable<Set<int>> positions, List<String> words})>
  _checkColumn(List<String?> board, int boardWidth, int boardHeight, int columnIndex) async {
    List<String> validWords = [];
    List<String> notValid = [];
    List<Set<int>> positions = [];
    String currentWord = "";
    Set<int> currentWordPositions = {};

    Future<void> flush() async {
      if (currentWord.length > 1) {
        if (await isValidWord(currentWord)) {
          validWords.add(currentWord);
          positions.add(currentWordPositions.toSet());
          _wordPositionsMap[currentWord] = currentWordPositions.toSet();
        } else {
          notValid.add(currentWord);
        }
      }
      currentWord = "";
      currentWordPositions = {};
    }

    for (int row = 0; row < boardHeight; row++) {
      int index = row * boardWidth + columnIndex;
      String? letter = board[index];
      if (letter != null) {
        currentWord += letter;
        currentWordPositions.add(index);
      } else {
        await flush();
      }
    }
    await flush();

    if (notValid.isEmpty) {
      return (words: validWords, positions: positions);
    } else {
      return (words: notValid, positions: <Set<int>>{});
    }
  }

  Future<({Iterable<Set<int>> positions, List<String> words})>
  _checkRow(List<String?> board, int boardWidth, int boardHeight, int rowIndex) async {
    List<String> validWords = [];
    List<String> notValid = [];
    List<Set<int>> positions = [];
    String currentWord = "";
    Set<int> currentWordPositions = {};

    Future<void> flush() async {
      if (currentWord.length > 1) {
        if (await isValidWord(currentWord)) {
          validWords.add(currentWord);
          positions.add(currentWordPositions.toSet());
          _wordPositionsMap[currentWord] = currentWordPositions.toSet();
        } else {
          notValid.add(currentWord);
        }
      }
      currentWord = "";
      currentWordPositions = {};
    }

    for (int col = 0; col < boardWidth; col++) {
      int index = rowIndex * boardWidth + col;
      String? letter = board[index];
      if (letter != null) {
        currentWord += letter;
        currentWordPositions.add(index);
      } else {
        await flush();
      }
    }
    await flush();

    if (notValid.isEmpty) {
      return (words: validWords, positions: positions);
    } else {
      return (words: notValid, positions: <Set<int>>{});
    }
  }

  // `board` must be exactly boardWidth * boardHeight long (no rack cells
  // mixed in -- callers should only ever pass the board portion of their
  // state).
  Future<WordCheckResult> findValidWords(
      List<String?> board, int boardWidth, int boardHeight) async {
    assert(board.length == boardWidth * boardHeight);
    _wordPositionsMap.clear();

    List<String> allValidWords = [];
    List<String> allInvalidWords = [];
    List<Set<int>> wordTilePositions = [];

    for (int col = 0; col < boardWidth; col++) {
      var result = await _checkColumn(board, boardWidth, boardHeight, col);
      if (result.words.isNotEmpty && await isValidWord(result.words.first)) {
        allValidWords.addAll(result.words);
        wordTilePositions.addAll(result.positions);
      } else {
        allInvalidWords.addAll(result.words);
      }
    }

    for (int row = 0; row < boardHeight; row++) {
      var result = await _checkRow(board, boardWidth, boardHeight, row);
      if (result.words.isNotEmpty && await isValidWord(result.words.first)) {
        allValidWords.addAll(result.words);
        wordTilePositions.addAll(result.positions);
      } else {
        allInvalidWords.addAll(result.words);
      }
    }

    // Check if all words are connected (every word shares at least one
    // tile position with some other word).
    bool areConnected = true;
    if (wordTilePositions.length > 1) {
      for (int i = 0; i < wordTilePositions.length; i++) {
        bool isConnected = false;
        for (int j = 0; j < wordTilePositions.length; j++) {
          if (i != j &&
              wordTilePositions[i].intersection(wordTilePositions[j]).isNotEmpty) {
            isConnected = true;
            break;
          }
        }
        if (!isConnected) {
          areConnected = false;
          break;
        }
      }
    }

    return WordCheckResult(
      words: allInvalidWords.isEmpty ? allValidWords : allInvalidWords,
      areValid: allInvalidWords.isEmpty,
      areConnected: areConnected,
    );
  }

  /// Every valid across and down word on the board, one WordRun per word
  /// in board order (across words row by row, then down words column by
  /// column), keeping repeats: two WELLs are two runs. [isValid] defaults
  /// to the dictionary; tests can pass a fake.
  Future<List<WordRun>> findValidRuns(
    List<String?> board,
    int boardWidth,
    int boardHeight, {
    Future<bool> Function(String word)? isValid,
  }) async {
    assert(board.length == boardWidth * boardHeight);
    final check = isValid ?? isValidWord;
    final runs = <WordRun>[];

    Future<void> scanLine(int count, int Function(int i) indexAt, bool across) async {
      var positions = <int>[];
      Future<void> flush() async {
        if (positions.length > 1) {
          final word = positions.map((i) => board[i]!).join();
          if (await check(word)) runs.add(WordRun(word, positions, across));
        }
        positions = <int>[];
      }

      for (int i = 0; i < count; i++) {
        final index = indexAt(i);
        if (board[index] != null) {
          positions.add(index);
        } else {
          await flush();
        }
      }
      await flush();
    }

    for (int row = 0; row < boardHeight; row++) {
      await scanLine(boardWidth, (col) => row * boardWidth + col, true);
    }
    for (int col = 0; col < boardWidth; col++) {
      await scanLine(boardHeight, (row) => row * boardWidth + col, false);
    }
    return runs;
  }

  String findWordFromPositions(Set<int> positions) {
    for (var entry in _wordPositionsMap.entries) {
      if (entry.value.toSet() == positions) {
        return entry.key;
      }
    }
    return "";
  }

  // The valid dictionary word (if any) that currently occupies `index`,
  // as of the most recent findValidWords call. Used for tap-for-definition:
  // only a word that's actually validly formed on the board right now
  // should show a definition.
  // Every valid word currently on the board (as of the most recent
  // findValidWords call) mapped to its tile positions. Used by Village
  // view to know which board cells belong to which word, so it can render
  // magic words as structures.
  Map<String, Set<int>> get validWordPositions => Map.unmodifiable(_wordPositionsMap);

  String? validWordContaining(int index) {
    for (final entry in _wordPositionsMap.entries) {
      if (entry.value.contains(index)) return entry.key;
    }
    return null;
  }
}
