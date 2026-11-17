// The Town Square (spec-13): bricks, the weekly vote, finishing a building.

import 'package:flutter_test/flutter_test.dart';

import 'package:namer_app/online/fake_family_backend.dart';
import 'package:namer_app/online/family_online_models.dart';
import 'package:namer_app/settings/word_level.dart';

const _nana = MemberInfo(name: 'Nana', colorIndex: 0, level: WordLevel.wordsmith);
const _sam = MemberInfo(name: 'Sam', colorIndex: 1, level: WordLevel.builder);

/// Nana starts a family and Sam (on his own phone) is let in.
Future<(FakeFamilyBackend nana, FakeFamilyBackend sam, String fid)> _family(FakeFamilyServer server) async {
  final nana = FakeFamilyBackend(server);
  await nana.signInWithGoogle();
  final f = await nana.createFamily(name: 'The Rivera family', me: _nana);
  final sam = FakeFamilyBackend(server)..googleEmail = 'sam@example.com';
  await sam.signInWithGoogle();
  await sam.requestToJoin(
      family: (await sam.findFamily(f.code))!, code: f.code, me: _sam, birthYear: 1990, group: AgeGroup.adult);
  await nana.approve(f.id, (await nana.watchFamily(f.id).first)!.requests.single);
  return (nana, sam, f.id);
}

void main() {
  // A Wednesday; its week starts Monday 2026-11-16.
  final wed = DateTime.utc(2026, 11, 18, 12);
  final nextMon = DateTime.utc(2026, 11, 23, 1);
  const two = ['a', 'b'];

  group('the rules', () {
    test('a week is keyed by its Monday (UTC)', () {
      expect(squareWeekKey(wed), '2026-11-16');
      expect(squareWeekKey(DateTime.utc(2026, 11, 16)), '2026-11-16');
      expect(squareWeekKey(DateTime.utc(2026, 11, 22, 23, 59)), '2026-11-16');
      expect(squareWeekKey(nextMon), '2026-11-23');
    });

    test('goal is 15 per member, at least 30', () {
      expect(squareGoal(1), 30);
      expect(squareGoal(2), 30);
      expect(squareGoal(3), 45);
      expect(squareGoal(6), 90);
    });

    test('a new square opens a vote with the first three buildings', () {
      final s = settleSquare(const TownSquare(), memberUids: two, now: wed);
      expect(s.voting, isTrue);
      expect(s.vote!.choices, ['fountain', 'bandstand', 'library']);
      expect(s.vote!.week, '2026-11-16');
    });

    test('everyone voting closes it; most votes wins', () {
      var s = pickSquareBuilding(const TownSquare(), 'a', 'library', memberUids: ['a', 'b', 'c'], now: wed);
      s = pickSquareBuilding(s, 'b', 'library', memberUids: ['a', 'b', 'c'], now: wed);
      expect(s.voting, isTrue);
      s = pickSquareBuilding(s, 'c', 'fountain', memberUids: ['a', 'b', 'c'], now: wed);
      expect(s.building, 'library');
      expect(s.goal, 45);
      expect(s.vote, isNull);
    });

    test('a tie goes to the one picked first', () {
      var s = pickSquareBuilding(const TownSquare(), 'a', 'bandstand', memberUids: two, now: wed);
      s = pickSquareBuilding(s, 'b', 'library', memberUids: two, now: wed.add(const Duration(minutes: 1)));
      expect(s.building, 'bandstand');
    });

    test('changing your mind is fine, and a pick outside the choices is ignored', () {
      var s = pickSquareBuilding(const TownSquare(), 'a', 'bakery', memberUids: two, now: wed);
      expect(s.vote!.picks, isEmpty);
      s = pickSquareBuilding(s, 'a', 'fountain', memberUids: two, now: wed);
      s = pickSquareBuilding(s, 'a', 'library', memberUids: two, now: wed);
      expect(s.vote!.picks, {'a': 'library'});
    });

    test('Monday closes the vote; with no votes the first choice wins', () {
      var s = settleSquare(const TownSquare(), memberUids: two, now: wed);
      s = settleSquare(s, memberUids: two, now: nextMon);
      expect(s.building, 'fountain');

      var t = pickSquareBuilding(const TownSquare(), 'a', 'library', memberUids: two, now: wed);
      t = settleSquare(t, memberUids: two, now: nextMon);
      expect(t.building, 'library');
    });

    test('bricks added while voting count toward the winner', () {
      var s = addSquareBricks(const TownSquare(), 5, memberUids: two, now: wed);
      expect(s.voting, isTrue);
      expect(s.progress, 5);
      s = pickSquareBuilding(s, 'a', 'fountain', memberUids: two, now: wed);
      s = pickSquareBuilding(s, 'b', 'fountain', memberUids: two, now: wed);
      expect(s.building, 'fountain');
      expect(s.progress, 5);
    });

    test('no more than 5 bricks at once', () {
      final s = addSquareBricks(const TownSquare(), 50, memberUids: two, now: wed);
      expect(s.bricks, 5);
    });

    test('a full bar finishes the building once and opens the next vote', () {
      var s = const TownSquare(building: 'fountain', goal: 30, bricks: 28);
      s = addSquareBricks(s, 5, memberUids: two, now: wed);
      expect(s.built.map((b) => b.id), ['fountain']);
      expect(s.built.single.on, '2026-11-18');
      expect(s.finishedOn, '2026-11-18');
      expect(s.voting, isTrue);
      expect(s.progress, 3, reason: 'extra bricks carry over');
      expect(s.vote!.choices, ['bandstand', 'library', 'garden']);
      // Settling again doesn't finish it twice.
      s = settleSquare(s, memberUids: two, now: wed);
      expect(s.built, hasLength(1));
    });

    test('saved and read back', () {
      var s = pickSquareBuilding(const TownSquare(), 'a', 'library', memberUids: two, now: wed);
      s = addSquareBricks(s, 4, memberUids: two, now: wed);
      final back = TownSquare.fromData(s.toData());
      expect(back.toData(), s.toData());
      expect(back.vote!.picks, {'a': 'library'});
      final built = TownSquare.fromData(const TownSquare(built: [BuiltThing('garden', '2026-11-01')]).toData());
      expect(built.built.single.id, 'garden');
    });
  });

  group('on the server', () {
    late FakeFamilyServer server;
    setUp(() => server = FakeFamilyServer());

    test('bricks from two phones add up, and both see the building finish', () async {
      final (nana, sam, fid) = await _family(server);
      final uids = [nana.account!.uid, sam.account!.uid];
      await nana.changeSquare(fid, (s) => pickSquareBuilding(s, uids[0], 'library', memberUids: uids, now: wed));
      await sam.changeSquare(fid, (s) => pickSquareBuilding(s, uids[1], 'library', memberUids: uids, now: wed));
      expect(sam.squareOf(fid).building, 'library');

      for (int i = 0; i < 6; i++) {
        await (i.isEven ? nana : sam).changeSquare(fid, (s) => addSquareBricks(s, 5, memberUids: uids, now: wed));
      }
      final square = nana.squareOf(fid);
      expect(square.built.map((b) => b.id), ['library']);
      expect(square.voting, isTrue);
      final seen = await sam.watchSquare(fid).first;
      expect(seen.built, hasLength(1));
    });

    test('the server refuses too many bricks or taking them away', () async {
      final (nana, _, fid) = await _family(server);
      await nana.changeSquare(fid, (s) => s.copyWith(bricks: 4));
      expect(() => nana.changeSquare(fid, (s) => s.copyWith(bricks: 20)), throwsStateError);
      expect(() => nana.changeSquare(fid, (s) => s.copyWith(bricks: 1)), throwsStateError);
      expect(nana.squareOf(fid).bricks, 4);
    });

    test('only members can see or change it', () async {
      final (_, _, fid) = await _family(server);
      final stranger = FakeFamilyBackend(server)..googleEmail = 'x@example.com';
      await stranger.signInWithGoogle();
      expect(() => stranger.changeSquare(fid, (s) => s), throwsStateError);
      expect(await stranger.watchSquare(fid).toList(), isEmpty);
    });
  });
}
