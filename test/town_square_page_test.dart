// The Town Square page (spec-13): an online family's Family page.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/daily/daily_seed.dart';
import 'package:namer_app/daily/word_of_the_day.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/online/fake_family_backend.dart';
import 'package:namer_app/online/family_online_controller.dart';
import 'package:namer_app/online/family_online_models.dart';
import 'package:namer_app/portfolio/portfolio_controller.dart';
import 'package:namer_app/settings/settings_controller.dart';
import 'package:namer_app/settings/word_level.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart';
import 'widget_test.dart' show loadAppFonts;

const _nana = MemberInfo(name: 'Nana', colorIndex: 0, level: WordLevel.wordsmith);
const _sam = MemberInfo(name: 'Sam', colorIndex: 1, level: WordLevel.builder);

/// Set SQUARE_PREVIEW=1 to write PNGs of the page to test/preview/ (for
/// looking at, not checked in).
final _preview = Platform.environment['SQUARE_PREVIEW'] == '1';

Future<void> _loadIcons() async {
  var dir = File(Platform.resolvedExecutable).parent;
  File f() => File('${dir.path}/material_fonts/materialicons-regular.otf');
  while (!f().existsSync() && dir.parent.path != dir.path) {
    dir = dir.parent;
    if (Directory('${dir.path}/artifacts').existsSync()) dir = Directory('${dir.path}/artifacts');
  }
  if (!f().existsSync()) return;
  final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(f().readAsBytesSync().buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    if (_preview) await _loadIcons();
  });
  final words = parseWordsOfTheDay(File('assets/words/word_of_the_day.json').readAsStringSync());

  late FakeFamilyServer server;
  late FakeFamilyBackend nana;
  late FakeFamilyBackend sam;
  late String fid;

  /// Nana (on this phone) and Sam (another phone) in an online family.
  Future<void> family(WidgetTester tester) async {
    await tester.runAsync(() async {
      server = FakeFamilyServer();
      nana = FakeFamilyBackend(server);
      await nana.signInWithGoogle();
      final f = await nana.createFamily(name: 'The Rivera family', me: _nana);
      sam = FakeFamilyBackend(server)..googleEmail = 'sam@example.com';
      await sam.signInWithGoogle();
      await sam.requestToJoin(
          family: (await sam.findFamily(f.code))!, code: f.code, me: _sam, birthYear: 1990, group: AgeGroup.adult);
      await nana.approve(f.id, (await nana.watchFamily(f.id).first)!.requests.single);
      fid = f.id;
    });
    SharedPreferences.setMockInitialValues({
      SettingsController.homeIntroSeenKey: true,
      FamilyOnlineController.prefsKey: jsonEncode({
        'familyId': fid,
        'uid': nana.account!.uid,
        'group': 'adult',
        'birthYear': 1958,
      }),
    });
  }

  Future<void> pumpHome(WidgetTester tester, {Size size = const Size(411, 891)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wordsOfTheDayProvider.overrideWith((ref) async => words),
        familyBackendFactoryProvider.overrideWithValue((id) async => nana),
      ],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    await goToHomePage(tester, 'Family');
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!_preview) return;
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/$name.png'));
  }

  testWidgets('a new online family sees the square and a vote', (tester) async {
    await family(tester);
    await pumpHome(tester);
    expect(find.text('The Rivera family'), findsOneWidget);
    expect(find.text('Vote for what to build'), findsOneWidget);
    expect(find.text('Fountain, Bandstand, Library?'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Nana \\(you\\)')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Sam: ')), findsOneWidget);
    // The vote opened on the server too.
    expect(nana.squareOf(fid).vote, isNotNull);
    await shot(tester, 'square_vote');

    await tester.tap(find.text('Vote'));
    await tester.pumpAndSettle();
    expect(find.text('What should we build next?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Library')));
    await tester.pumpAndSettle();
    expect(find.text("Sam hasn't voted yet."), findsOneWidget);
    await shot(tester, 'vote_screen');

    // Sam votes on his phone: it's decided.
    await tester.runAsync(() => sam.changeSquare(
        fid,
        (s) => pickSquareBuilding(s, sam.account!.uid, 'library',
            memberUids: [nana.account!.uid, sam.account!.uid], now: DateTime.now())));
    await tester.pumpAndSettle();
    expect(find.text("It's decided: the Library!"), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Building: Library'), findsOneWidget);
    expect(find.text('0 / 30'), findsOneWidget);
  });

  testWidgets('building: the bar, How to add bricks, and the gift badge', (tester) async {
    await family(tester);
    final uids = [nana.account!.uid, sam.account!.uid];
    await tester.runAsync(() async {
      await sam.changeSquare(fid, (s) => pickSquareBuilding(s, uids[0], 'fountain', memberUids: uids, now: DateTime.now()));
      await sam.changeSquare(fid, (s) => pickSquareBuilding(s, uids[1], 'fountain', memberUids: uids, now: DateTime.now()));
      for (int i = 0; i < 3; i++) {
        await sam.changeSquare(fid, (s) => addSquareBricks(s, 5, memberUids: uids, now: DateTime.now()));
      }
      await sam.sendNote(
          fid,
          FamilyNote(
              kind: NoteKind.gift, from: uids[1], to: uids[0], day: dailyDateKey(DateTime.now()), letter: 'E', at: 1));
    });
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpHome(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Building: Fountain'), findsOneWidget);
    expect(find.text('15 / 30'), findsOneWidget);
    expect(find.bySemanticsLabel('From your family, 1 new'), findsOneWidget);
    // Fits one screen at the Samsung's text size: the card ends above the tabs.
    expect(tester.getRect(find.text('How to add bricks')).bottom, lessThan(891 - 80));
    await shot(tester, 'square_building');

    await tester.tap(find.text('How to add bricks'));
    await tester.pumpAndSettle();
    expect(find.text('Fountain: 15 bricks to go'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    await shot(tester, 'bricks_screen');
  });

  testWidgets('the bar fills: We built it!, +15 coins once, and it stands in the square', (tester) async {
    await family(tester);
    final uids = [nana.account!.uid, sam.account!.uid];
    await tester.runAsync(() async {
      await sam.changeSquare(fid, (s) => pickSquareBuilding(s, uids[0], 'bandstand', memberUids: uids, now: DateTime.now()));
      await sam.changeSquare(fid, (s) => pickSquareBuilding(s, uids[1], 'bandstand', memberUids: uids, now: DateTime.now()));
      for (int i = 0; i < 5; i++) {
        await sam.changeSquare(fid, (s) => addSquareBricks(s, 5, memberUids: uids, now: DateTime.now()));
      }
    });
    await pumpHome(tester);
    expect(find.text('25 / 30'), findsOneWidget);
    expect(find.text('We built it!'), findsNothing);

    // Sam's Daily puts in the last bricks.
    await tester.runAsync(() => sam.changeSquare(fid, (s) => addSquareBricks(s, 5, memberUids: uids, now: DateTime.now())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('We built it!'), findsOneWidget);
    expect(find.textContaining('built a Bandstand'), findsOneWidget);
    await shot(tester, 'we_built_it');
    await tester.tap(find.text('Hooray!'));
    await tester.pumpAndSettle();
    expect(find.text('We built it!'), findsNothing);
    expect(find.bySemanticsLabel('Bandstand, built by the family'), findsOneWidget);
    expect(find.text('Vote for what to build'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    expect(container.read(portfolioProvider).currency, 15);

    // Coming back to Home doesn't pay again.
    await tester.tap(find.text('Vote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('We built it!'), findsNothing);
    expect(container.read(portfolioProvider).currency, 15);
  });

  testWidgets('Extra large text: no overflow', (tester) async {
    await family(tester);
    SharedPreferences.setMockInitialValues({
      ...{for (final k in (await SharedPreferences.getInstance()).getKeys()) k: (await SharedPreferences.getInstance()).get(k)!},
      'textSizeStep': 2,
    });
    await pumpHome(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('Vote for what to build'), findsOneWidget);
  });
}
