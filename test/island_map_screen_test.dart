import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/island_map.dart';
import 'package:namer_app/screens/island_map_screen.dart';

void main() {
  const home = 250 * 500 + 250;
  final map = IslandMap(seed: 1, homes: const [home]);

  test('the middle of the map picture is home', () {
    expect(cellAtMapPoint(const Offset(200, 300), const Size(400, 600), map), home);
  });

  test('a point right of the middle is a cell east of home', () {
    // 400 wide shows 190 cells, so 40px is about 19 cells.
    final cell = cellAtMapPoint(const Offset(240, 300), const Size(400, 600), map);
    expect(cell ~/ 500, 250);
    expect(cell % 500, inInclusiveRange(268, 270));
  });
}
