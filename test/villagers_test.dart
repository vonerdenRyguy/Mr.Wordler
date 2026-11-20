import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/explore/island_map.dart';
import 'package:namer_app/game/word_runs.dart';
import 'package:namer_app/settings/word_level.dart';
import 'package:namer_app/villagers/topic_words.dart';
import 'package:namer_app/villagers/village_book.dart';
import 'package:namer_app/villagers/villager_names.dart';
import 'package:namer_app/villagers/wish.dart';

WordRun _run(String word, {int start = 1000}) =>
    WordRun(word, [for (var i = 0; i < word.length; i++) start + i], true);

Ring _meadow(int _) => Ring.meadow;

void main() {
  group('topic words', () {
    test('8 topics with plenty of words, all 3+ letters A-Z, and enough short ones for Sprout', () {
      expect(kTopics.length, 8);
      for (final t in kTopics) {
        expect(t.words.length, greaterThanOrEqualTo(30), reason: t.id);
        expect(t.shortWords.length, greaterThanOrEqualTo(12), reason: t.id);
        expect(t.shortWords.every((w) => w.length >= 3 && w.length <= 4), isTrue);
        for (final w in t.words) {
          expect(RegExp(r'^[A-Z]{3,}$').hasMatch(w), isTrue, reason: '${t.id}: $w');
        }
        expect(t.words.toSet().length, t.words.length, reason: '${t.id} has a repeat');
      }
    });

    test('every topic word is in the real dictionary', () {
      final dictionary = File('lib_assests/words.txt')
          .readAsLinesSync()
          .map((l) => l.trim().toLowerCase())
          .toSet();
      final missing = [
        for (final t in kTopics)
          for (final w in t.words)
            if (!dictionary.contains(w.toLowerCase())) '${t.id}:$w',
      ];
      expect(missing, isEmpty);
    });
  });

  group('names', () {
    test('four distinct choices, stable per villager, different between villagers', () {
      final a = nameChoicesFor('v0');
      expect(a.toSet().length, 4);
      expect(nameChoicesFor('v0'), a);
      expect(nameChoicesFor('v1'), isNot(a));
    });

    test('names already taken are skipped', () {
      final a = nameChoicesFor('v3');
      final b = nameChoicesFor('v3', taken: {a.first});
      expect(b, isNot(contains(a.first)));
    });

    test('a typed name is trimmed and capped at 12 letters; blank keeps the old name', () {
      expect(cleanVillagerName('  Sir   Pip  '), 'Sir Pip');
      expect(cleanVillagerName('Abcdefghijklmnopqrst'), 'Abcdefghijkl');
      expect(cleanVillagerName('   '), isNull);
      expect(cleanVillagerName('Zoë 🐸'), 'Zoë 🐸');
    });
  });

  group('wishes', () {
    test('describe, per kind', () {
      expect(const Wish.topic('animals').describe(), 'an animal');
      expect(const Wish.topic('weather').describe(), 'a word about weather');
      expect(const Wish.length(3).describe(), 'a 3-letter word');
      expect(const Wish.length(6, exactly: false).describe(), 'a word with 6+ letters');
      expect(const Wish.letter('B').describe(), 'a word with B');
      expect(const Wish.letter('S', starts: true).describe(), 'a word that starts with S');
      expect(const Wish.letter('ZQXJ').describe(), 'a word with a Z, Q, X or J');
      expect(const Wish.place(Wish.nearMe).describe(), 'a word next to me');
      expect(const Wish.place('river').describe(), 'a word touching the river');
      expect(const Wish.place('forest').describe(), 'a word that reaches the forest');
    });

    test('JSON round trip; a damaged wish is dropped', () {
      for (final w in [
        const Wish.topic('food'),
        const Wish.length(4),
        const Wish.length(7, exactly: false),
        const Wish.letter('KVW'),
        const Wish.letter('T', starts: true),
        const Wish.place('hills'),
      ]) {
        expect(Wish.fromJson(w.toJson()), w);
      }
      expect(Wish.fromJson({'k': 'topic', 't': 'nope'}), isNull);
      expect(Wish.fromJson('x'), isNull);
    });

    bool met(Wish w, WordRun r, {Ring Function(int)? ringAt, int home = 1000}) =>
        wishMetBy(w, r, homeCell: home, ringAt: ringAt ?? _meadow);

    test('topic, length, letter', () {
      expect(met(const Wish.topic('animals'), _run('HORSE')), isTrue);
      expect(met(const Wish.topic('animals'), _run('TABLE')), isFalse);
      expect(met(const Wish.length(4), _run('WELL')), isTrue);
      expect(met(const Wish.length(4), _run('WELLS')), isFalse);
      expect(met(const Wish.length(6, exactly: false), _run('GARDENS')), isTrue);
      expect(met(const Wish.length(6, exactly: false), _run('GARDE')), isFalse);
      expect(met(const Wish.letter('B'), _run('CAB')), isTrue);
      expect(met(const Wish.letter('B'), _run('CAT')), isFalse);
      expect(met(const Wish.letter('S', starts: true), _run('SUN')), isTrue);
      expect(met(const Wish.letter('S', starts: true), _run('MUSS')), isFalse);
      expect(met(const Wish.letter('ZQXJ'), _run('JAM')), isTrue);
      expect(met(const Wish.letter('ZQXJ'), _run('JAM'.replaceAll('J', 'H'))), isFalse);
    });

    test('place: next to me is within 2 squares of the home cell', () {
      const home = 250 * 500 + 250;
      expect(met(const Wish.place(Wish.nearMe), _run('CAT', start: home + 2), home: home), isTrue);
      expect(met(const Wish.place(Wish.nearMe), _run('CAT', start: home + 3), home: home), isFalse);
      // 2 rows away counts too.
      expect(met(const Wish.place(Wish.nearMe), WordRun('CAT', [home + 1000, home + 1001, home + 1002], true), home: home),
          isTrue);
    });

    test('place: rings, and the river counts from the bank', () {
      Ring ringAt(int cell) => cell % 500 >= 300 ? Ring.forest : (cell % 500 == 299 ? Ring.river : Ring.meadow);
      expect(met(const Wish.place('forest'), _run('CAT', start: 300), ringAt: ringAt), isTrue);
      expect(met(const Wish.place('forest'), _run('CAT', start: 100), ringAt: ringAt), isFalse);
      // A word ending on 298 sits next to the river cell 299.
      expect(met(const Wish.place('river'), _run('CAT', start: 296), ringAt: ringAt), isTrue);
      expect(met(const Wish.place('river'), _run('CAT', start: 100), ringAt: ringAt), isFalse);
    });

    test('Sprout is only offered short topic words and easy wishes', () {
      final all = wishesFor(WordLevel.sprout);
      expect(all.where((w) => w.kind == WishKind.length).every((w) => w.number <= 4), isTrue);
      expect(all.where((w) => w.kind == WishKind.place).map((w) => w.place).toSet(), {Wish.nearMe});
      final rng = math.Random(1);
      for (final t in kTopics) {
        final w = exampleWord(Wish.topic(t.id), WordLevel.sprout, rng)!;
        expect(w.length, lessThanOrEqualTo(4));
        expect(t.hasWord(w), isTrue);
      }
    });

    test('place wishes only appear for rings you can see', () {
      expect(wishesFor(WordLevel.wordsmith).where((w) => w.kind == WishKind.place).map((w) => w.place).toSet(),
          {Wish.nearMe});
      expect(
          wishesFor(WordLevel.wordsmith, seenRings: {Ring.forest, Ring.hills})
              .where((w) => w.kind == WishKind.place)
              .map((w) => w.place)
              .toSet(),
          {Wish.nearMe, 'forest', 'hills'});
      expect(
          wishesFor(WordLevel.explorer, seenRings: {Ring.river})
              .where((w) => w.kind == WishKind.place)
              .map((w) => w.place)
              .toSet(),
          {Wish.nearMe, 'river'});
    });

    test('chooseWish never repeats the last wish and avoids ones already met when it can', () {
      final rng = math.Random(7);
      const last = Wish.topic('water');
      for (var i = 0; i < 200; i++) {
        final w = chooseWish(WordLevel.explorer, rng, previous: last, alreadyMet: (w) => w.kind == WishKind.topic);
        expect(w, isNot(last));
        expect(w.kind, isNot(WishKind.topic));
      }
      // If everything is already met it still gives a wish.
      expect(chooseWish(WordLevel.sprout, rng, alreadyMet: (_) => true), isA<Wish>());
    });

    test('every kind of wish shows up at every level', () {
      for (final level in WordLevel.values) {
        final kinds = wishesFor(level).map((w) => w.kind).toSet();
        expect(kinds, {WishKind.topic, WishKind.length, WishKind.letter, WishKind.place}, reason: '$level');
      }
    });

    test('exampleWord fits the wish', () {
      final rng = math.Random(3);
      final long = exampleWord(const Wish.length(7, exactly: false), WordLevel.wordsmith, rng)!;
      expect(long.length, greaterThanOrEqualTo(7));
      final z = exampleWord(const Wish.letter('S', starts: true), WordLevel.explorer, rng)!;
      expect(z.startsWith('S'), isTrue);
    });
  });

  group('VillagerBook', () {
    const v0 = Villager(id: 'v0', name: 'Pip', cell: 1000, movedInWord: 'SIPS', wish: Wish.topic('water'));
    final now = DateTime.utc(2026, 11, 21, 9);

    VillagerBook book([Villager v = v0]) => VillagerBook([v]);

    ({VillagerBook book, List<WishGranted> granted}) check(VillagerBook b, List<WordRun> runs, [DateTime? at]) =>
        b.checkWishes(runs, now: at ?? now, ringAt: _meadow);

    test('moving in happens once', () {
      final b = const VillagerBook().moveIn(v0);
      expect(b.count, 1);
      expect(b.moveIn(v0.copyWith(name: 'Other')).byId('v0')!.name, 'Pip');
    });

    test('a spelled wish gives a heart, once, and schedules tomorrow', () {
      final r = check(book(), [_run('RAIN')]);
      expect(r.granted.length, 1);
      final g = r.granted.single;
      expect(g.coins, kWishCoins);
      expect(g.xp, kWishXp);
      expect(g.becameBestFriend, isFalse);
      final v = r.book.byId('v0')!;
      expect(v.hearts, 1);
      expect(v.granted, 1);
      expect(v.wish, isNull);
      expect(v.nextWishOn, '2026-11-22');
      // Same words again: nothing more (no wish to grant).
      expect(check(r.book, [_run('RAIN')]).granted, isEmpty);
    });

    test('a word already on the board counts; a wrong word does not', () {
      expect(check(book(), [_run('TABLE')]).granted, isEmpty);
      expect(check(book(), [_run('TABLE'), _run('POND')]).granted.length, 1);
    });

    test('the next wish arrives the next day, not before', () {
      var b = check(book(), [_run('RAIN')]).book;
      var made = 0;
      Wish newWish(Villager _) {
        made++;
        return const Wish.length(4);
      }

      expect(b.refreshWishes(now, newWish).byId('v0')!.wish, isNull);
      expect(made, 0);
      expect(b.refreshWishes(DateTime.utc(2026, 11, 21, 23, 59), newWish).byId('v0')!.wish, isNull);
      final next = b.refreshWishes(DateTime.utc(2026, 11, 22, 0, 1), newWish);
      expect(next.byId('v0')!.wish, const Wish.length(4));
      expect(next.byId('v0')!.nextWishOn, isNull);
      // A day later than that still works (they were away).
      b = b.refreshWishes(DateTime.utc(2026, 12, 30), newWish);
      expect(b.byId('v0')!.wish, isNotNull);
    });

    test('5 hearts: best friend and the present exactly once', () {
      var b = book(v0.copyWith(hearts: 4));
      var r = check(b, [_run('RAIN')]);
      expect(r.granted.single.becameBestFriend, isTrue);
      expect(r.granted.single.coins, kWishCoins + kBestFriendCoins);
      expect(r.book.byId('v0')!.bestFriend, isTrue);
      // Next day, another wish comes true: hearts stay at 5, no second present.
      b = r.book.refreshWishes(DateTime.utc(2026, 11, 22), (_) => const Wish.topic('water'));
      r = check(b, [_run('LAKE')], DateTime.utc(2026, 11, 22));
      expect(r.granted.single.becameBestFriend, isFalse);
      expect(r.granted.single.coins, kWishCoins);
      expect(r.book.byId('v0')!.hearts, 5);
    });

    test('Different wish is free, any number of times, only while a wish is open', () {
      var b = book();
      for (var i = 0; i < 10; i++) {
        b = b.swapWish('v0', Wish.length(3 + i % 2));
      }
      expect(b.byId('v0')!.wish, const Wish.length(4));
      expect(b.byId('v0')!.hearts, 0);
      final waiting = check(b, [_run('WELL')]).book;
      expect(waiting.byId('v0')!.wish, isNull);
      expect(waiting.swapWish('v0', const Wish.topic('food')).byId('v0')!.wish, isNull);
    });

    test('rename and JSON round trip', () {
      final b = check(book(), [_run('RAIN')]).book.rename('v0', 'Sir Pip');
      final again = VillagerBook.fromJson(b.toJson());
      expect(again.byId('v0')!.name, 'Sir Pip');
      expect(again.byId('v0')!.hearts, 1);
      expect(again.byId('v0')!.nextWishOn, '2026-11-22');
      expect(again.byId('v0')!.movedInWord, 'SIPS');
      expect(VillagerBook.fromJson('garbage').isEmpty, isTrue);
      expect(VillagerBook.fromJson([1, 'x', v0.toJson()]).count, 1);
    });
  });
}
