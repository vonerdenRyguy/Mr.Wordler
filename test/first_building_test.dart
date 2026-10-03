import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/word_runs.dart';
import 'package:namer_app/village/structures.dart';
import 'package:namer_app/village/village_rewards.dart';

void main() {
  final well = computeStructures(const [WordRun('WELL', [0, 1, 2, 3], true)]);
  final wellAndFarm = computeStructures(const [
    WordRun('WELL', [0, 1, 2, 3], true),
    WordRun('FARM', [10, 11, 12, 13], true),
  ]);

  test('discovering WELL pays 10 coins once', () {
    final discovered = <String>{};
    final first = newDiscoveries(well, discovered);
    expect(coinsForDiscoveries(first), 10);
    discovered.addAll(first);
    expect(coinsForDiscoveries(newDiscoveries(well, discovered)), 0);
  });

  test('building it again after removing it pays nothing', () {
    final discovered = <String>{'WELL'};
    expect(coinsForDiscoveries(newDiscoveries(const [], discovered)), 0); // removed
    expect(coinsForDiscoveries(newDiscoveries(well, discovered)), 0); // rebuilt
  });

  test('a save that already discovered WELL pays nothing on load', () {
    expect(newDiscoveries(well, {'WELL'}), isEmpty);
  });

  test('two new buildings at once pay 20', () {
    expect(coinsForDiscoveries(newDiscoveries(wellAndFarm, {})), 20);
  });
}
