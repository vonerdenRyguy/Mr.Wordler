// Family online (spec-08): age groups, family codes, the join-and-say-yes
// flow on the in-memory fake server, the per-player controller, and the
// sign-in and account screens.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:namer_app/daily/daily_seed.dart';
import 'package:namer_app/online/fake_family_backend.dart';
import 'package:namer_app/online/family_online_controller.dart';
import 'package:namer_app/online/family_online_models.dart';
import 'package:namer_app/players/players.dart';
import 'package:namer_app/screens/family_online_screens.dart';
import 'package:namer_app/settings/word_level.dart';
import 'package:namer_app/ui/tokens.dart';

const _nana = MemberInfo(name: 'Nana', colorIndex: 0, level: WordLevel.wordsmith);
const _leo = MemberInfo(name: 'Leo', colorIndex: 3, level: WordLevel.sprout);
const _sam = MemberInfo(name: 'Sam', colorIndex: 1, level: WordLevel.builder);
const _dad = MemberInfo(name: 'Dad', colorIndex: 4, level: WordLevel.wordsmith);
final _now = DateTime.utc(2026, 11, 15, 12);

Future<void> _settle() async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Nana starts a family on her own phone and returns her backend.
Future<(FakeFamilyBackend, OnlineFamily)> _nanaStarts(FakeFamilyServer server) async {
  final nana = FakeFamilyBackend(server);
  await nana.signInWithGoogle();
  final family = await nana.createFamily(name: 'The Rivera family', me: _nana);
  return (nana, family);
}

Future<OnlineFamily?> _latest(FakeFamilyBackend backend, String familyId) => backend.watchFamily(familyId).first;

void main() {
  test('age groups: under 13 is a child, 13 to 17 a teen, 18 and over a grown-up', () {
    expect(ageGroupFor(birthYear: 2018, birthMonth: 3, now: _now), AgeGroup.child);
    // Turns 13 in December 2026: still 12 in November.
    expect(ageGroupFor(birthYear: 2013, birthMonth: 12, now: _now), AgeGroup.child);
    expect(ageGroupFor(birthYear: 2013, birthMonth: 11, now: _now), AgeGroup.teen);
    expect(ageGroupFor(birthYear: 2008, birthMonth: 12, now: _now), AgeGroup.teen);
    expect(ageGroupFor(birthYear: 2008, birthMonth: 11, now: _now), AgeGroup.adult);
    expect(ageGroupFor(birthYear: 1958, birthMonth: 3, now: _now), AgeGroup.adult);
  });

  test('family codes are a friendly word and four digits, typed any way', () {
    final random = Random(7);
    for (int i = 0; i < 200; i++) {
      final code = newFamilyCode(random);
      expect(code, matches(RegExp(r'^[A-Z]{4}[2-9]{4}$')));
      expect(kCodeWords, contains(code.substring(0, 4)));
      expect(normalizeFamilyCode(code), code);
    }
    expect(normalizeFamilyCode('bear 4821'), 'BEAR4821');
    expect(normalizeFamilyCode('Bear-4821'), 'BEAR4821');
    expect(normalizeFamilyCode('BEAR482'), isNull);
    expect(normalizeFamilyCode('4821BEAR'), isNull);
    expect(showFamilyCode('BEAR4821'), 'BEAR 4821');
    expect(const OnlineAccount(uid: 'u', method: SignInMethod.email, email: 'nana@example.com').maskedEmail,
        'n•••@example.com');
  });

  test('a child asks with the code, sees only grown-up names, and gets in on a yes', () async {
    final server = FakeFamilyServer();
    final (nana, family) = await _nanaStarts(server);
    expect(family.members.single.adult, isTrue);

    // Sam (a teen) is already in, to check the preview never names children.
    final sam = FakeFamilyBackend(server)..googleEmail = 'sam@example.com';
    await sam.signInWithGoogle();
    final preview0 = (await sam.findFamily(family.code))!;
    await sam.requestToJoin(family: preview0, code: family.code, me: _sam, birthYear: 2010, group: AgeGroup.teen);
    await nana.approve(family.id, (await _latest(nana, family.id))!.requests.single);

    final leo = FakeFamilyBackend(server);
    await leo.signInAsChild();
    expect(leo.account!.email, isNull);
    expect(await leo.findFamily('LAKE9999'), isNull);
    final preview = (await leo.findFamily(family.code))!;
    expect(preview.name, 'The Rivera family');
    expect(preview.adultNames, ['Nana']);

    // A code alone isn't enough: Leo can't see the family yet.
    await leo.requestToJoin(family: preview, code: family.code, me: _leo, birthYear: 2018, group: AgeGroup.child);
    expect(await leo.watchRequest(family.id).first, RequestStatus.waiting);
    expect(await _latest(leo, family.id), isNull);
    // Only grown-ups see requests.
    expect((await _latest(sam, family.id))!.requests, isEmpty);
    final request = (await _latest(nana, family.id))!.requests.single;
    expect(request.name, 'Leo');
    expect(request.birthYear, 2018);
    expect(request.group, AgeGroup.child);
    expect(() => sam.approve(family.id, request), throwsStateError);

    await nana.approve(family.id, request);
    expect(await leo.watchRequest(family.id).first, RequestStatus.accepted);
    final seenByLeo = (await _latest(leo, family.id))!;
    expect([for (final m in seenByLeo.members) m.name], ['Nana', 'Sam', 'Leo']);
    expect(seenByLeo.member(leo.account!.uid)!.adult, isFalse);
    expect(seenByLeo.requests, isEmpty);

    // Leo finishes his Daily; Nana sees it.
    await leo.setPlayedDay(family.id, '2026-11-15');
    final seenByNana = (await _latest(nana, family.id))!;
    expect(seenByNana.member(leo.account!.uid)!.playedOn('2026-11-15'), isTrue);
    expect(seenByNana.member(sam.account!.uid)!.playedOn('2026-11-15'), isFalse);
  });

  test('a grown-up let in can say yes too; not now, a new code, leaving and deleting', () async {
    final server = FakeFamilyServer();
    final (nana, family) = await _nanaStarts(server);

    final dad = FakeFamilyBackend(server)..googleEmail = 'dad@example.com';
    await dad.signInWithGoogle();
    await dad.requestToJoin(
        family: (await dad.findFamily(family.code))!, code: family.code, me: _dad, birthYear: 1985, group: AgeGroup.adult);
    await nana.approve(family.id, (await _latest(nana, family.id))!.requests.single);
    expect((await dad.findFamily(family.code))!.adultNames, ['Nana', 'Dad']);

    // Dad says not now to a stranger who got hold of the code.
    final stranger = FakeFamilyBackend(server);
    await stranger.signInAsChild();
    await stranger.requestToJoin(
        family: (await stranger.findFamily(family.code))!, code: family.code, me: _leo, birthYear: 2016, group: AgeGroup.child);
    await dad.decline(family.id, (await _latest(dad, family.id))!.requests.single);
    expect(await stranger.watchRequest(family.id).first, RequestStatus.declined);

    // A new code: the old one stops finding the family.
    final newCode = await nana.newCode(family.id);
    expect(newCode, isNot(family.code));
    expect(await stranger.findFamily(family.code), isNull);
    expect((await stranger.findFamily(newCode))!.familyId, family.id);

    await dad.leave(family.id);
    expect(await _latest(dad, family.id), isNull);
    expect((await _latest(nana, family.id))!.members, hasLength(1));

    // The last one out closes the family.
    await nana.deleteAccount(family.id);
    expect(nana.account, isNull);
    expect(server.familyCount, 0);
    expect(await stranger.findFamily(newCode), isNull);
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

    test('with no Firebase the feature says so and Daily finishing does nothing', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(familyOnlineProvider.notifier);
      await controller.ready;
      expect(container.read(familyOnlineProvider).stage, OnlineStage.unavailable);
      await controller.markPlayed(_now); // no throw
    });

    test('signs in, starts a family, and remembers it after a restart', () async {
      final container = make();
      final controller = container.read(familyOnlineProvider.notifier);
      await controller.ready;
      expect(container.read(familyOnlineProvider).stage, OnlineStage.signedOut);

      expect(await controller.signInWithGoogle(birthYear: 1958, group: AgeGroup.adult), isTrue);
      expect(container.read(familyOnlineProvider).stage, OnlineStage.noFamily);
      expect(server.profiles.values.single, {'birthYear': 1958, 'group': 'adult'});

      await controller.createFamily(name: 'The Rivera family', me: _nana);
      await _settle();
      var s = container.read(familyOnlineProvider);
      expect(s.stage, OnlineStage.member);
      expect(s.family!.name, 'The Rivera family');
      expect(s.me!.adult, isTrue);

      await controller.markPlayed(_now);
      await _settle();
      expect(container.read(familyOnlineProvider).me!.playedOn('2026-11-15'), isTrue);

      final saved = jsonDecode((await SharedPreferences.getInstance()).getString('familyOnlineData')!) as Map;
      expect(saved['familyId'], s.familyId);
      container.dispose();

      // The app restarts: same backend (still signed in), family from the save.
      final again = make();
      addTearDown(again.dispose);
      await again.read(familyOnlineProvider.notifier).ready;
      await _settle();
      s = again.read(familyOnlineProvider);
      expect(s.stage, OnlineStage.member);
      expect(s.group, AgeGroup.adult);
      expect(s.family!.members.single.name, 'Nana');
    });

    test('a grown-up who signs out, tries a child sign-in, then signs back in gets their family back', () async {
      final container = make();
      addTearDown(container.dispose);
      final controller = container.read(familyOnlineProvider.notifier);
      await controller.ready;
      await controller.signInWithGoogle(birthYear: 1958, group: AgeGroup.adult);
      await controller.createFamily(name: 'The Rivera family', me: _nana);
      await _settle();
      final family = container.read(familyOnlineProvider).family!;

      await controller.signOut();
      await controller.signInAsChild(birthYear: 2018);
      final preview = (await controller.findFamily(family.code))!;
      await controller.requestToJoin(family: preview, code: family.code, me: _leo);
      await _settle();
      await controller.cancelRequest();
      await controller.signOut();

      await controller.signInWithGoogle(birthYear: 1958, group: AgeGroup.adult);
      await _settle();
      final s = container.read(familyOnlineProvider);
      expect(s.stage, OnlineStage.member);
      expect(s.family!.id, family.id);
      expect(s.me!.adult, isTrue);
      expect(s.family!.requests, isEmpty);
    });

    test('signing back in after being removed clears the old family', () async {
      final (nana, family) = await _nanaStarts(server);
      final container = make();
      addTearDown(container.dispose);
      final controller = container.read(familyOnlineProvider.notifier);
      await controller.ready;
      backends.values.single.googleEmail = 'sam@example.com';
      await controller.signInWithGoogle(birthYear: 1990, group: AgeGroup.adult);
      final preview = (await controller.findFamily(family.code))!;
      await controller.requestToJoin(family: preview, code: family.code, me: _leo);
      await nana.approve(family.id, (await _latest(nana, family.id))!.requests.single);
      await _settle();
      expect(container.read(familyOnlineProvider).stage, OnlineStage.member);

      await controller.signOut();
      await nana.removeMember(family.id, (await _latest(nana, family.id))!.members.firstWhere((m) => m.name == 'Leo').uid);
      await controller.signInWithGoogle(birthYear: 1990, group: AgeGroup.adult);
      await _settle();
      expect(container.read(familyOnlineProvider).stage, OnlineStage.noFamily);
      expect(server.profiles.values.last['familyId'], isNull);
    });

    test('a child waits, is turned down, asks again and gets in', () async {
      final (nana, family) = await _nanaStarts(server);
      final container = make();
      addTearDown(container.dispose);
      final controller = container.read(familyOnlineProvider.notifier);
      await controller.ready;
      await controller.signInAsChild(birthYear: 2018);
      expect(container.read(familyOnlineProvider).group, AgeGroup.child);
      // No birth month is kept, only the year.
      expect(server.profiles.values.last.containsKey('birthMonth'), isFalse);

      final preview = (await controller.findFamily(family.code))!;
      await controller.requestToJoin(family: preview, code: family.code, me: _leo);
      await _settle();
      expect(container.read(familyOnlineProvider).stage, OnlineStage.waiting);
      expect(container.read(familyOnlineProvider).waitingFor!.adultNames, ['Nana']);

      await nana.decline(family.id, (await _latest(nana, family.id))!.requests.single);
      await _settle();
      expect(container.read(familyOnlineProvider).stage, OnlineStage.noFamily);
      expect(container.read(familyOnlineProvider).declined, isTrue);

      await controller.requestToJoin(family: preview, code: family.code, me: _leo);
      await nana.approve(family.id, (await _latest(nana, family.id))!.requests.single);
      await _settle();
      final s = container.read(familyOnlineProvider);
      expect(s.stage, OnlineStage.member);
      expect(s.me!.name, 'Leo');
      expect(s.me!.adult, isFalse);
      expect(server.profiles[s.account!.uid]!['familyId'], family.id);

      // A grown-up removes Leo: he's back to no family.
      await nana.removeMember(family.id, s.account!.uid);
      await _settle();
      expect(container.read(familyOnlineProvider).stage, OnlineStage.noFamily);
    });

    test('each player on the phone has their own sign-in and family', () async {
      SharedPreferences.setMockInitialValues({
        'playersData': jsonEncode({
          'players': [
            {'id': 'p1', 'name': 'Nana', 'colorIndex': 0},
            {'id': 'p2', 'name': 'Leo', 'colorIndex': 3},
          ],
          'currentId': 'p1',
          'nextNumber': 3,
        }),
      });
      final container = make();
      addTearDown(container.dispose);
      await container.read(playersProvider.notifier).ready;
      var controller = container.read(familyOnlineProvider.notifier);
      await controller.ready;
      await controller.signInWithGoogle(birthYear: 1958, group: AgeGroup.adult);
      await controller.createFamily(name: 'The Rivera family', me: _nana);
      await _settle();

      await container.read(playersProvider.notifier).select('p2');
      controller = container.read(familyOnlineProvider.notifier);
      await controller.ready;
      expect(container.read(familyOnlineProvider).stage, OnlineStage.signedOut);
      expect(backends.keys, ['p1', 'p2']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('familyOnlineData'), isNotNull);
      expect(prefs.getString('p2_familyOnlineData'), isNull);
    });
  });

  group('screens', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlayerKeys.prefix = '';
    });

    Widget app(FakeFamilyServer server, Widget home, {FakeFamilyBackend? backend}) => ProviderScope(
          overrides: [
            familyBackendFactoryProvider.overrideWithValue((id) async => backend ?? FakeFamilyBackend(server)),
          ],
          child: MaterialApp(theme: buildWordlerTheme(), home: home),
        );

    testWidgets('sign in asks the age first; under 13 never sees an email box', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(FakeFamilyServer(), SignInScreen(now: _now)));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsNothing);

      Future<void> pick(String hint, String value) async {
        await tester.tap(find.text(hint).last, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(find.text(value).last);
        await tester.pumpAndSettle();
      }

      await pick('Month', 'March');
      await pick('Year', '2018');
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.byType(TextField), findsNothing);

      // 13 to 17: Google or an emailed link.
      await pick('2018', '2012');
      expect(find.text('Next'), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Email me a sign-in link'), findsOneWidget);
    });

    testWidgets('before signing in: what is shared, and that there is no chat', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(FakeFamilyServer(), FamilyOnlineScreen(key: UniqueKey())));
      await tester.pumpAndSettle();
      expect(find.text('Letters you give or ask for'), findsOneWidget);
      expect(find.text('Cheers you send: a sticker and your name'), findsOneWidget);
      expect(find.text('Typed messages: there is no chat'), findsOneWidget);
      expect(find.text('Anything to or from people outside the family'), findsOneWidget);
    });

    testWidgets('a grown-up sees who asked, and the family with who played', (tester) async {
      final server = FakeFamilyServer();
      final (nana, family) = await _nanaStarts(server);
      final leo = FakeFamilyBackend(server);
      await leo.signInAsChild();
      await leo.requestToJoin(
          family: (await leo.findFamily(family.code))!, code: family.code, me: _leo, birthYear: 2018, group: AgeGroup.child);
      await nana.setPlayedDay(family.id, dailyDateKey(DateTime.now()));
      SharedPreferences.setMockInitialValues({
        'familyOnlineData': jsonEncode({'familyId': family.id, 'birthYear': 1958, 'group': 'adult'}),
      });

      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(server, FamilyOnlineScreen(key: UniqueKey()), backend: nana));
      await tester.pumpAndSettle();

      expect(find.text('Leo wants to join'), findsOneWidget);
      expect(find.textContaining('Born 2018 · Under 13'), findsOneWidget);
      expect(find.text(showFamilyCode(family.code)), findsOneWidget);
      expect(find.text('Played'), findsOneWidget);
      expect(find.textContaining('Letters and cheer stickers Leo sends'), findsOneWidget);

      await tester.tap(find.text('Yes, Leo can join'));
      await tester.pumpAndSettle();
      expect(find.text('Leo wants to join'), findsNothing);
      expect(find.text('Leo'), findsOneWidget);
      expect(find.text('Not yet'), findsOneWidget);
    });
  });
}
