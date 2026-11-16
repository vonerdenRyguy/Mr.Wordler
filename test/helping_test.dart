// Helping each other (spec-10): letter gifts, asking for a letter, cheers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:namer_app/daily/daily_seed.dart';
import 'package:namer_app/game/grid_config.dart';
import 'package:namer_app/game/grid_game_controller.dart';
import 'package:namer_app/online/fake_family_backend.dart';
import 'package:namer_app/online/family_online_controller.dart';
import 'package:namer_app/online/family_online_models.dart';
import 'package:namer_app/online/helping.dart';
import 'package:namer_app/players/players.dart';
import 'package:namer_app/screens/family_word_online_screens.dart';
import 'package:namer_app/screens/helping_screens.dart';
import 'package:namer_app/settings/word_level.dart';
import 'package:namer_app/ui/tokens.dart';

const _nana = MemberInfo(name: 'Nana', colorIndex: 0, level: WordLevel.wordsmith);
const _sam = MemberInfo(name: 'Sam', colorIndex: 1, level: WordLevel.builder);

Future<void> _settle() async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

FamilyNote _gift(String from, String to, String letter, String day, {String id = '', int at = 0}) =>
    FamilyNote(id: id, kind: NoteKind.gift, from: from, to: to, day: day, letter: letter, at: at);

void main() {
  final today = dailyDateKey(DateTime.now());

  group('the rules', () {
    test('three gifts a day each; yesterday does not count', () {
      final notes = [
        _gift('a', 'b', 'E', today),
        _gift('a', 'c', 'K', today),
        _gift('a', 'b', 'Q', 'yesterday'),
        _gift('b', 'a', 'S', today),
      ];
      expect(giftsLeft(notes, 'a', today), 1);
      expect(giftsLeft(notes, 'b', today), 2);
      expect(giftsLeft([...notes, _gift('a', 'c', 'Z', today), _gift('a', 'c', 'Z', today)], 'a', today), 0);
    });

    test('a request is answered by a gift of that letter today', () {
      final sam = OnlineMember(
          uid: 's', name: 'Sam', colorIndex: 1, level: WordLevel.builder, adult: true, wants: 'E', wantsOn: today);
      expect(openRequest(sam, const [], today), 'E');
      expect(openRequest(sam, [_gift('a', 's', 'K', today)], today), 'E', reason: 'a K is not an E');
      expect(openRequest(sam, [_gift('a', 's', 'E', today)], today), isNull);
      expect(openRequest(sam, const [], 'tomorrow'), isNull, reason: 'requests last one day');
    });

    test('waiting gifts: oldest first, and each one only once', () {
      final notes = [
        _gift('a', 'me', 'B', today, id: 'n2', at: 2),
        _gift('a', 'me', 'A', today, id: 'n1', at: 1),
        _gift('a', 'other', 'C', today, id: 'n3', at: 3),
      ];
      expect([for (final g in waitingGifts(notes, 'me', {})) g.letter], ['A', 'B']);
      expect([for (final g in waitingGifts(notes, 'me', {'n1'})) g.letter], ['B']);
    });

    test('a gift goes on top of the rack, not from the pool', () {
      final c = GridGameController(const GridConfig(
        boardWidth: 10,
        boardHeight: 10,
        rackSize: 10,
        randomSeed: 7,
        refillRackOnPlace: true,
      ));
      final pool = c.state.pool.length;
      final i = c.addGiftLetter('Q');
      expect(i, 10);
      expect(c.state.rackCells, hasLength(11));
      expect(c.state.rackCells[10], 'Q');
      expect(c.state.pool, hasLength(pool));
    });
  });

  group('the server', () {
    late FakeFamilyServer server;

    setUp(() => server = FakeFamilyServer());

    test("can't send as someone else, to yourself, or outside the family", () async {
      final (nana, sam, fid) = await _family(server);
      final n = nana.account!.uid, s = sam.account!.uid;
      await expectLater(nana.sendNote(fid, _gift(s, n, 'E', today)), throwsStateError);
      await expectLater(nana.sendNote(fid, _gift(n, n, 'E', today)), throwsStateError);
      await expectLater(nana.sendNote(fid, _gift(n, 'stranger', 'E', today)), throwsStateError);
      await expectLater(nana.sendNote(fid, _gift(n, s, 'EE', today)), throwsStateError, reason: 'one letter');
      final outsider = FakeFamilyBackend(server)..googleEmail = 'x@example.com';
      await outsider.signInWithGoogle();
      await expectLater(outsider.sendNote(fid, _gift(outsider.account!.uid, s, 'E', today)), throwsStateError);
      await nana.sendNote(fid, _gift(n, s, 'E', today));
      expect(nana.allNotes(fid), hasLength(1));
    });
  });

  group('controller', () {
    late FakeFamilyServer server;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlayerKeys.prefix = '';
      server = FakeFamilyServer();
    });

    Future<(ProviderContainer, FakeFamilyBackend sam, String fid)> asNana() async {
      final (nana, sam, fid) = await _family(server);
      SharedPreferences.setMockInitialValues({
        'familyOnlineData': '{"familyId":"$fid","birthYear":1958,"group":"adult"}',
      });
      final c = ProviderContainer(overrides: [
        familyBackendFactoryProvider.overrideWithValue((id) async => nana),
      ]);
      c.read(familyOnlineProvider);
      await c.read(familyOnlineProvider.notifier).ready;
      await _settle();
      return (c, sam, fid);
    }

    test('give three letters; the fourth waits for tomorrow', () async {
      final (c, sam, fid) = await asNana();
      addTearDown(c.dispose);
      final online = c.read(familyOnlineProvider.notifier);
      final s = sam.account!.uid;
      expect(online.giftsLeftToday, 3);
      expect(await online.giveLetter(s, 'e'), isTrue);
      expect(await online.giveLetter(s, 'K'), isTrue);
      expect(await online.giveLetter(s, 'S'), isTrue);
      await _settle();
      expect(online.giftsLeftToday, 0);
      expect(await online.giveLetter(s, 'T'), isFalse);
      expect([for (final n in sam.allNotes(fid)) n.letter], ['E', 'K', 'S']);
    });

    test('ask for a letter; someone sends it; it lands once', () async {
      final (c, sam, fid) = await asNana();
      addTearDown(c.dispose);
      final online = c.read(familyOnlineProvider.notifier);
      expect(await online.askFor('R'), isTrue);
      await _settle();
      expect(online.myOpenRequest, 'R');

      // Sam sees it and sends one.
      final nanaUid = c.read(familyOnlineProvider).account!.uid;
      final seen = (await sam.watchFamily(fid).first)!.member(nanaUid)!;
      expect(seen.wantsOnDay(today), 'R');
      await sam.sendNote(fid, _gift(sam.account!.uid, nanaUid, 'R', today, at: 5));
      await _settle();
      expect(online.myOpenRequest, isNull, reason: 'answered');
      expect(online.waitingGiftsForMe.single.letter, 'R');

      final taken = await online.takeGifts();
      expect(taken.single.letter, 'R');
      expect(await online.takeGifts(), isEmpty, reason: 'each gift arrives once');
    });

    test('a cheer arrives with who sent it and what it was for', () async {
      final (c, sam, fid) = await asNana();
      addTearDown(c.dispose);
      final nanaUid = c.read(familyOnlineProvider).account!.uid;
      await sam.sendNote(
        fid,
        FamilyNote(kind: NoteKind.cheer, from: sam.account!.uid, to: nanaUid, day: today, sticker: 'highfive', about: 'MILL'),
      );
      await _settle();
      final items = myHelpItems(c.read(familyOnlineProvider));
      expect(items.single.note!.sticker, 'highfive');
      expect(items.single.note!.about, 'MILL');
    });
  });

  group('screens', () {
    late FakeFamilyServer server;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlayerKeys.prefix = '';
      server = FakeFamilyServer();
    });

    Future<(FakeFamilyBackend nana, FakeFamilyBackend sam, String fid)> setup() async {
      final r = await _family(server);
      SharedPreferences.setMockInitialValues({
        'familyOnlineData': '{"familyId":"${r.$3}","birthYear":1958,"group":"adult"}',
      });
      return r;
    }

    Widget app(FakeFamilyBackend backend, Widget home) => ProviderScope(
          overrides: [familyBackendFactoryProvider.overrideWithValue((id) async => backend)],
          child: MaterialApp(theme: buildWordlerTheme(), home: home),
        );

    testWidgets("Sam's plot: his request, Give a letter and Cheer!", (tester) async {
      final (nana, sam, fid) = await setup();
      await sam.setWants(fid, 'E', today);
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(nana, PlotScreen(uid: sam.account!.uid)));
      await tester.pumpAndSettle();

      expect(find.text('SAM IS LOOKING FOR'), findsOneWidget);
      expect(find.text('Send Sam an E'), findsOneWidget);
      expect(find.text('Give a letter'), findsOneWidget);
      expect(find.text('Cheer!'), findsOneWidget);
      expect(find.text('3 letters left to give today'), findsOneWidget);

      await tester.tap(find.text('Send Sam an E'));
      await tester.pumpAndSettle();
      expect(find.text('Sent Sam an E!'), findsOneWidget);
      expect(find.text('SAM IS LOOKING FOR'), findsNothing, reason: 'answered');
      expect(find.text('2 letters left to give today'), findsOneWidget);
    });

    testWidgets('give a letter: pick it, send it', (tester) async {
      final (nana, sam, fid) = await setup();
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(nana, GiveLetterScreen(uid: sam.account!.uid)));
      await tester.pumpAndSettle();
      expect(find.text('Pick a letter'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('K'));
      await tester.pumpAndSettle();
      expect(find.text('2 left after this one today'), findsOneWidget);
      await tester.tap(find.text('Send the K'));
      await tester.pumpAndSettle();
      expect(sam.allNotes(fid).single.letter, 'K');
    });

    testWidgets('cheer: swipe for more stickers, send one', (tester) async {
      final (nana, sam, fid) = await setup();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(nana, CheerScreen(uid: sam.account!.uid)));
      await tester.pumpAndSettle();
      expect(find.text('Wow!'), findsOneWidget);
      expect(find.text('So smart!'), findsNothing);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('So smart!'), findsOneWidget);
      await tester.tap(find.text('So smart!'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send So smart!'));
      await tester.pumpAndSettle();
      expect(sam.allNotes(fid).single.sticker, 'smart');
    });

    testWidgets('From your family: gifts, cheers and requests', (tester) async {
      final (nana, sam, fid) = await setup();
      final n = nana.account!.uid, s = sam.account!.uid;
      await sam.sendNote(fid, _gift(s, n, 'K', today, at: 1));
      await sam.sendNote(fid, FamilyNote(kind: NoteKind.cheer, from: s, to: n, day: today, sticker: 'highfive', at: 2));
      await sam.setWants(fid, 'R', today);
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(nana, const FromFamilyScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('sent you a '), findsOneWidget);
      expect(find.textContaining('High five!'), findsOneWidget);
      expect(find.textContaining('is looking for an R'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(find.textContaining('there is no chat'), findsOneWidget);
    });

    testWidgets('three gifts arrive: one box, Say thank you', (tester) async {
      final (nana, sam, fid) = await setup();
      final n = nana.account!.uid, s = sam.account!.uid;
      for (final (i, l) in ['E', 'A', 'S'].indexed) {
        await sam.sendNote(fid, _gift(s, n, l, today, at: i + 1));
      }
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(
        nana,
        Consumer(
          builder: (context, ref, _) {
            // Home keeps the family loaded, as the app does.
            ref.watch(familyOnlineProvider);
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final gifts = await ref.read(familyOnlineProvider.notifier).takeGifts();
                    if (context.mounted) await showGiftsArrived(context, ref, gifts);
                  },
                  child: const Text('Visit'),
                ),
              ),
            );
          },
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visit'));
      await tester.pumpAndSettle();
      expect(find.text('Sam sent you 3 letters!'), findsOneWidget);
      expect(find.textContaining("They're in your rack"), findsOneWidget);
      await tester.tap(find.text('Say thank you'));
      await tester.pumpAndSettle();
      expect(find.text('Sam sent you 3 letters!'), findsNothing);
      final thanks = [for (final x in sam.allNotes(fid)) if (x.kind == NoteKind.cheer) x];
      expect(thanks.single.sticker, kThankYouSticker, reason: 'one thank-you per sender');
    });
  });
}
