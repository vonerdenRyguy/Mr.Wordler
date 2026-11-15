import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/daily_puzzle.dart';
import 'package:namer_app/daily/share_card.dart';
import 'package:namer_app/portfolio/property_tier.dart';

void main() {
  String share({bool completed = true, bool found = true, int clues = 0}) => buildDailyShareText(
        dateKey: '2026-11-14',
        completed: completed,
        timeSeconds: 125,
        streak: 3,
        tier: PropertyTier.house,
        bonusWordFound: found,
        themeName: 'Animals',
        cluesUsed: clues,
      );

  test('the share text has the theme and says when no clues were used', () {
    final text = share();
    expect(text, contains('Daily puzzle'));
    expect(text, contains('Theme: Animals'));
    expect(text, contains('02:05'));
    expect(text, contains('Secret word found! (no clues)'));
    expect(share(clues: 2), isNot(contains('(no clues)')));
    expect(share(found: false), isNot(contains('Secret word')));
    expect(share(completed: false), contains('Gave up today'));
  });

  test('the share text never contains the secret word', () {
    final puzzle = dailyPuzzleFor(DateTime.utc(2026, 11, 14));
    final text = buildDailyShareText(
      dateKey: '2026-11-14',
      completed: true,
      timeSeconds: 60,
      streak: 1,
      tier: PropertyTier.cottage,
      bonusWordFound: true,
      themeName: puzzle.theme.name,
    );
    expect(text.toUpperCase(), isNot(contains(puzzle.secretWord)));
  });

  test('boardContainsWord: whole runs only, across or down', () {
    List<String?> board(Map<int, String> cells) => [for (int i = 0; i < 100; i++) cells[i]];
    final across = board({20: 'C', 21: 'A', 22: 'T'});
    final down = board({5: 'C', 15: 'A', 25: 'T'});
    final longer = board({20: 'C', 21: 'A', 22: 'T', 23: 'S'});
    final wrapped = board({8: 'C', 9: 'A', 10: 'T'});
    expect(boardContainsWord(across, 10, 10, 'cat'), isTrue);
    expect(boardContainsWord(down, 10, 10, 'CAT'), isTrue);
    expect(boardContainsWord(longer, 10, 10, 'CAT'), isFalse);
    expect(boardContainsWord(wrapped, 10, 10, 'CAT'), isFalse);
  });

  test('hideWordInMeaning replaces the word itself, any case, whole words only', () {
    expect(hideWordInMeaning('A Horse is a horse. Horses run.', 'HORSE'), 'A this is a this. Horses run.');
  });
}
