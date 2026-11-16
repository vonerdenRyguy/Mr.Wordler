// The family word and family map online (spec-09): shares in any order,
// guesses, coins once a day each, the streak, buildings, and the screens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:namer_app/daily/daily_seed.dart';
import 'package:namer_app/daily/word_of_the_day.dart';
import 'package:namer_app/online/fake_family_backend.dart';
import 'package:namer_app/online/family_online_controller.dart';
import 'package:namer_app/online/family_online_models.dart';
import 'package:namer_app/players/family_word.dart';
import 'package:namer_app/players/players.dart';
import 'package:namer_app/screens/family_word_online_screens.dart';
import 'package:namer_app/settings/word_level.dart';
import 'package:namer_app/ui/tokens.dart';

const _nana = MemberInfo(name: 'Nana', colorIndex: 0, level: WordLevel.wordsmith);
const _leo = MemberInfo(name: 'Leo', colorIndex: 3, level: WordLevel.sprout);
const _sam = MemberInfo(name: 'Sam', colorIndex: 1, level: WordLevel.builder);
const _lantern = WordOfDay(word: 'LANTERN', meaning: 'A light you can carry.');

Future<void> _settle() async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('sharing out the letters', () {
    final order = [3, 0, 6, 1, 5, 2, 4]; // 7 letters
    const members = ['a', 'b', 'c'];

    List<int> play(List<String> who) {
      var day = const FamilyDay();
      for (final u in who) {
        day = uncoverShare(day, uid: u, revealOrder: order, memberUids: members);
      }
      expect(day.solved, isTrue, reason: 'everyone played, so the word is out');
      expect(day.revealed.length, 7);
      return [for (final u in who) day.found[u]!.length];
    }

    test('any order: the shares are the same sizes and the last one finishes it', () {
      expect(play(['a', 'b', 'c']), [3, 2, 2]);
      expect(play(['c', 'a', 'b']), [3, 2, 2]);
      var day = const FamilyDay();
      day = uncoverShare(day, uid: 'b', revealOrder: order, memberUids: members);
      day = uncoverShare(day, uid: 'c', revealOrder: order, memberUids: members);
      expect(day.solved, isFalse, reason: 'a has not played yet');
      day = uncoverShare(day, uid: 'a', revealOrder: order, memberUids: members);
      expect(day.solvedBy, 'a');
      expect(day.solvedEarly, isFalse);
    });

    test('playing twice changes nothing', () {
      final once = uncoverShare(const FamilyDay(), uid: 'a', revealOrder: order, memberUids: members);
      final twice = uncoverShare(once, uid: 'a', revealOrder: order, memberUids: members);
      expect(twice.found, once.found);
    });

    test('a guess finds it early and carries the streak on', () {
      const yesterday = FamilyDay(solved: true, streak: 2);
      final day = solveByGuess(const FamilyDay(), uid: 'b', yesterday: yesterday);
      expect(day.solved && day.solvedEarly, isTrue);
      expect(day.streak, 3);
      expect(solveByGuess(const FamilyDay(), uid: 'b', yesterday: const FamilyDay()).streak, 1);
    });
  });

  group('controller', () {
    late FakeFamilyServer server;
    late Map<String, FakeFamilyBackend> backends;

    ProviderContainer make() => ProviderContainer(overrides: [
          familyBackendFactoryProvider.overrideWithValue(
            (id) async => backends.putIfAbsent(id, () => FakeFamilyBackend(server)),
          ),
        ]);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlayerKeys.prefix = '';
      server = FakeFamilyServer();
      backends = {};
    });

    /// Nana (this player, on the controller) starts a family; Leo, on
    /// another phone, is let in. Returns Leo's backend and the family id.
    Future<(FakeFamilyBackend, String)> family(ProviderContainer c) async {
      final controller = c.read(familyOnlineProvider.notifier);
      await controller.ready;
      await controller.signInWithGoogle(birthYear: 1958, group: AgeGroup.adult);
      await controller.createFamily(name: 'The Rivera family', me: _nana);
      await _settle();
      final fid = c.read(familyOnlineProvider).familyId!;
      final code = c.read(familyOnlineProvider).family!.code;
      final leo = FakeFamilyBackend(server);
      await leo.signInAsChild();
      await leo.requestToJoin(
          family: (await leo.findFamily(code))!, code: code, me: _leo, birthYear: 2018, group: AgeGroup.child);
      await _settle();
      await controller.approve(c.read(familyOnlineProvider).family!.requests.single);
      await _settle();
      return (leo, fid);
    }

    test('two people, either order: the last one finishes it and coins come once', () async {
      final c = make();
      addTearDown(c.dispose);
      final (leo, fid) = await family(c);
      final controller = c.read(familyOnlineProvider.notifier);
      final now = DateTime.now();
      final key = dailyDateKey(now);
      final yesterday = dailyDateKey(now.subtract(const Duration(days: 1)));

      // Leo plays first, on his phone.
      final members = [for (final m in c.read(familyOnlineProvider).family!.members) m.uid];
      await leo.changeDay(fid, key,
          yesterdayKey: yesterday,
          change: (t, y) => uncoverShare(t,
              uid: leo.account!.uid, revealOrder: familyRevealOrder('LANTERN', now), memberUids: members, yesterday: y));
      await _settle();
      var day = c.read(familyOnlineProvider).day!;
      expect(day.found[leo.account!.uid], hasLength(4));
      expect(day.solved, isFalse);
      expect(await controller.claimWordCoins(), 0);

      // Then Nana: the rest comes out.
      final mine = await controller.recordPlayed(now: now, word: 'LANTERN');
      expect(mine, hasLength(3));
      await _settle();
      day = c.read(familyOnlineProvider).day!;
      expect(day.solved, isTrue);
      expect(day.solvedEarly, isFalse);
      expect(day.solvedBy, c.read(familyOnlineProvider).account!.uid);

      expect(await controller.claimWordCoins(), kFamilyWordCoins);
      expect(await controller.claimWordCoins(), 0, reason: 'once a day');
      // Playing again changes nothing.
      expect(await controller.recordPlayed(now: now, word: 'LANTERN'), hasLength(3));
    });

    test('a right guess finds it early (+20); a wrong one changes nothing', () async {
      final c = make();
      addTearDown(c.dispose);
      final (leo, fid) = await family(c);
      final controller = c.read(familyOnlineProvider.notifier);
      final now = DateTime.now();
      // Yesterday the family found it too: the streak goes on.
      await leo.changeDay(fid, dailyDateKey(now.subtract(const Duration(days: 1))),
          yesterdayKey: dailyDateKey(now.subtract(const Duration(days: 2))),
          change: (t, y) => solveByGuess(t, uid: leo.account!.uid, yesterday: y));

      expect(await controller.guess(text: 'LANTERNS', now: now, word: 'LANTERN'), isFalse);
      await _settle();
      expect(c.read(familyOnlineProvider).day!.solved, isFalse);

      expect(await controller.guess(text: ' lantern ', now: now, word: 'LANTERN'), isTrue);
      await _settle();
      final day = c.read(familyOnlineProvider).day!;
      expect(day.solvedEarly, isTrue);
      expect(day.streak, 2);
      // Today's +20 and yesterday's +20 (not collected yet on this phone).
      expect(await controller.claimWordCoins(), 2 * kFamilyWordEarlyCoins);
    });

    test("nobody can take someone else's letters, and a found word stays found", () async {
      final c = make();
      addTearDown(c.dispose);
      final (leo, fid) = await family(c);
      final controller = c.read(familyOnlineProvider.notifier);
      final now = DateTime.now();
      final key = dailyDateKey(now);
      await controller.recordPlayed(now: now, word: 'LANTERN');
      final nanaUid = c.read(familyOnlineProvider).account!.uid;
      await expectLater(
        leo.changeDay(fid, key,
            yesterdayKey: 'x', change: (t, y) => FamilyDay(found: {...t.found, nanaUid: const [0]})),
        throwsStateError,
      );
      await controller.guess(text: 'LANTERN', now: now, word: 'LANTERN');
      await expectLater(
        leo.changeDay(fid, key, yesterdayKey: 'x', change: (t, y) => FamilyDay(found: t.found)),
        throwsStateError,
      );
    });

    test('buildings: the first send has nothing new; later ones mark what went up', () async {
      final c = make();
      addTearDown(c.dispose);
      final (leo, fid) = await family(c);
      final controller = c.read(familyOnlineProvider.notifier);
      await controller.syncBuildings({'WELL': 1, 'BARN': 1});
      await _settle();
      var me = c.read(familyOnlineProvider).me!;
      expect(me.buildingCount, 2);
      expect(me.newOnDay(dailyDateKey(DateTime.now())), isEmpty);

      await controller.syncBuildings({'WELL': 2, 'BARN': 1, 'FARM': 1});
      await _settle();
      me = c.read(familyOnlineProvider).me!;
      expect(me.buildingCount, 4);
      expect(me.newOnDay(dailyDateKey(DateTime.now())), unorderedEquals(['WELL', 'FARM']));

      // A brand new village: the empty first send counts, so the first
      // building ever is new today.
      final c2 = make();
      addTearDown(c2.dispose);
      final fresh = c2.read(familyOnlineProvider.notifier);
      await family(c2);
      await fresh.syncBuildings({});
      await _settle();
      await fresh.syncBuildings({'FARM': 1});
      await _settle();
      expect(c2.read(familyOnlineProvider).me!.newOnDay(dailyDateKey(DateTime.now())), ['FARM']);

      // Leo sees them; nothing else about the village is there to see.
      final seen = (await leo.watchFamily(fid).first)!.member(me.uid)!;
      expect(seen.buildings, {'WELL': 2, 'BARN': 1, 'FARM': 1});
    });
  });

  group('screens', () {
    late FakeFamilyServer server;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlayerKeys.prefix = '';
      server = FakeFamilyServer();
    });

    Future<FakeFamilyBackend> nanaWithFamily({bool samPlayed = false}) async {
      final nana = FakeFamilyBackend(server);
      await nana.signInWithGoogle();
      final f = await nana.createFamily(name: 'The Rivera family', me: _nana);
      final sam = FakeFamilyBackend(server)..googleEmail = 'sam@example.com';
      await sam.signInWithGoogle();
      await sam.requestToJoin(
          family: (await sam.findFamily(f.code))!, code: f.code, me: _sam, birthYear: 1990, group: AgeGroup.adult);
      await nana.approve(f.id, (await nana.watchFamily(f.id).first)!.requests.single);
      await sam.updateBuildings(f.id, buildings: {'WELL': 2, 'MILL': 1}, newBuildings: ['MILL'],
          newOn: dailyDateKey(DateTime.now()));
      if (samPlayed) {
        final now = DateTime.now();
        await sam.changeDay(f.id, dailyDateKey(now),
            yesterdayKey: 'x',
            change: (t, y) => uncoverShare(t,
                uid: sam.account!.uid,
                revealOrder: familyRevealOrder('LANTERN', now),
                memberUids: [nana.account!.uid, sam.account!.uid]));
      }
      SharedPreferences.setMockInitialValues({
        'familyOnlineData': '{"familyId":"${f.id}","birthYear":1958,"group":"adult"}',
      });
      return nana;
    }

    Widget app(FakeFamilyBackend backend, Widget home) => ProviderScope(
          overrides: [
            familyBackendFactoryProvider.overrideWithValue((id) async => backend),
            wordsOfTheDayProvider.overrideWith((ref) async => const [_lantern]),
          ],
          child: MaterialApp(theme: buildWordlerTheme(), home: home),
        );

    testWidgets('the family word: letters by whoever played, any order, any time', (tester) async {
      final nana = await nanaWithFamily(samPlayed: true);
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(nana, const OnlineFamilyWordScreen()));
      await tester.pumpAndSettle();

      expect(find.text('A light you can carry.'), findsOneWidget);
      expect(find.text('4 of 7 letters found. The colored edge shows who found each one.'), findsOneWidget);
      expect(find.textContaining('Found '), findsOneWidget); // Sam's row
      expect(find.text('Any time today'), findsOneWidget); // Nana's
      expect(find.text('Play my puzzle'), findsOneWidget);
    });

    testWidgets('the map shows each plot with its count; a plot shows only buildings', (tester) async {
      final nana = await nanaWithFamily();
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(nana, const FamilyMapScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Town Square'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // Sam's buildings
      expect(find.text('Your plot: 0 buildings'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Sam: 3 buildings'));
      await tester.pumpAndSettle();
      expect(find.text("Sam's plot"), findsOneWidget);
      expect(find.text('Well'), findsOneWidget);
      expect(find.text('x2'), findsOneWidget);
      expect(find.text('new today'), findsOneWidget);
      expect(find.textContaining('Only Sam'), findsOneWidget);
    });
  });
}
