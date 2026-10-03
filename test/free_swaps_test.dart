import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/village/village_rewards.dart';

void main() {
  test('no Farm: the first swap is free, the second costs 5', () {
    expect(nextSwapCost(used: 0, hasFarm: false), 0);
    expect(nextSwapCost(used: 1, hasFarm: false), 5);
  });

  test('with a Farm: the first two are free, the third costs 5', () {
    expect(freeSwapsLeft(used: 0, hasFarm: true), 2);
    expect(nextSwapCost(used: 0, hasFarm: true), 0);
    expect(nextSwapCost(used: 1, hasFarm: true), 0);
    expect(nextSwapCost(used: 2, hasFarm: true), 5);
  });

  test('a new visit starts the count again', () {
    // The screen keeps `used` in its state, which starts at 0 each time
    // the screen opens.
    expect(nextSwapCost(used: 0, hasFarm: false), 0);
  });
}
