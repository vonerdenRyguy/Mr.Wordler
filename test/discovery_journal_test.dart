import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/village/discovery_journal_view.dart';

void main() {
  test('counts full credit when the rack has every letter needed', () {
    expect(lettersTowardWord('WELL', ['W', 'E', 'L', 'L', null, 'X']), 4);
  });

  test('counts partial credit for a partly-stocked rack', () {
    expect(lettersTowardWord('BRIDGE', ['B', 'R', 'I', null, null, null]), 3);
  });

  test('respects duplicate-letter requirements rather than just checking presence', () {
    // WELL needs two L's; a rack with only one L should count 3, not 4.
    expect(lettersTowardWord('WELL', ['W', 'E', 'L', 'X']), 3);
  });

  test('an empty rack counts zero toward any word', () {
    expect(lettersTowardWord('FARM', List<String?>.filled(21, null)), 0);
  });

  test('extra unrelated letters in the rack do not inflate the count', () {
    expect(lettersTowardWord('MILL', ['Z', 'Q', 'X', 'Y']), 0);
  });
}
