import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/village/landmark.dart';

void main() {
  test('every landmark index is inside the board bounds', () {
    const boardWidth = 60;
    const boardHeight = 60;
    final indices = landmarkBoardIndices(boardWidth, boardHeight);

    expect(indices, isNotEmpty);
    for (final index in indices) {
      expect(index, greaterThanOrEqualTo(0));
      expect(index, lessThan(boardWidth * boardHeight));
    }
  });

  test('landmarks are distinct positions, not stacked on each other', () {
    final indices = landmarkBoardIndices(60, 60);
    expect(indices.toSet().length, indices.length);
  });

  test('landmarks get farther from the origin as the list goes on', () {
    const boardWidth = 60;
    const boardHeight = 60;
    const centerRow = boardHeight ~/ 2;
    const centerCol = boardWidth ~/ 2;
    final indices = landmarkBoardIndices(boardWidth, boardHeight);

    double distanceFromCenter(int index) {
      final row = index ~/ boardWidth;
      final col = index % boardWidth;
      return sqrt(pow(row - centerRow, 2) + pow(col - centerCol, 2));
    }

    final distances = indices.map(distanceFromCenter).toList();
    for (int i = 1; i < distances.length; i++) {
      expect(distances[i], greaterThan(distances[i - 1]),
          reason: 'landmark $i should be farther out than landmark ${i - 1}');
    }
  });

  test('is deterministic for a given board size', () {
    final first = landmarkBoardIndices(60, 60);
    final second = landmarkBoardIndices(60, 60);
    expect(first, second);
  });
}
