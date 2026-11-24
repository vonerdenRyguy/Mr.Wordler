// spec-17: loose letters go back to the rack on leaving and, once, on the
// first load of an older village (save v5).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/portfolio/portfolio_controller.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart' show skipHomeIntro;

const _size = 500;
const _mid = _size ~/ 2;
const _key = 'infiniteEstateVillageSave';
// Q sits away from WELL, with nothing around it.
const _qCell = (_mid + 5) * _size + _mid;

Map<String, dynamic> _save({required int version, bool tidied = false, int note = 0, bool withQ = true}) {
  final board = List<String?>.filled(_size * _size, null);
  'WELL'.split('').asMap().forEach((i, l) => board[_mid * _size + _mid - 3 + i] = l);
  if (withQ) board[_qCell] = 'Q';
  return {
    'boardCells': board,
    'rackCells': List<String>.filled(10, 'E'),
    'pool': List<String>.filled(50, 'E'),
    'dealtLetters': [...'WELL'.split(''), ...List<String>.filled(10, 'E')],
    'lastCashedOutScore': 0,
    'discoveredWords': ['WELL'],
    'saveVersion': version,
    if (version >= 5) 'tidiedLoose': tidied,
    if (version >= 5) 'looseNote': note,
    if (version >= 6) 'planet': {'slot': 0},
  };
}

void main() {
  // Pumps until the village has settled, noting whether Mr. W's note showed
  // (it goes away by itself after a few seconds).
  var sawNote = false;
  Future<void> pumpVillage(WidgetTester tester) async {
    sawNote = false;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('Mr. W put').evaluate().isNotEmpty) sawNote = true;
    }
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> openVillage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await skipHomeIntro();
    await tester.pumpWidget(ProviderScope(
      overrides: [wordCheckProvider.overrideWithValue((w) async => w == 'WELL')],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('home-my-village'))));
    await tester.tap(find.byKey(const ValueKey('home-my-village')));
    await pumpVillage(tester);
    return container;
  }

  Future<Map<String, dynamic>> savedJson() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return jsonDecode(prefs.getString(_key)!) as Map<String, dynamic>;
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave Village'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  testWidgets('a v4 village with a stray letter tidies once, saves the current version and says so', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode(_save(version: 4))});
    final container = await openVillage(tester);

    expect(sawNote, isTrue);
    expect(container.read(portfolioProvider).currency, 0); // nothing earned or lost
    var json = await savedJson();
    expect(json['saveVersion'], 6);
    expect(json['tidiedLoose'], true);
    expect(json['looseNote'], 0); // told
    expect((json['boardCells'] as List)[_qCell], isNull);
    expect((json['boardCells'] as List).whereType<String>().join(), 'WELL');
    expect((json['rackCells'] as List).whereType<String>().length, 10);
    expect(json['bag'], ['Q']); // the rack was full, so the Q waits in the bag
    expect((json['discoveredWords'] as List), ['WELL']);

    // A second visit changes nothing and says nothing.
    await leave(tester);
    await tester.tap(find.byKey(const ValueKey('home-my-village')));
    await pumpVillage(tester);
    expect(sawNote, isFalse);
    json = await savedJson();
    expect((json['rackCells'] as List).whereType<String>().length, 10);
    expect(json['bag'], ['Q']);
    expect((json['boardCells'] as List).whereType<String>().join(), 'WELL');
  });

  testWidgets('leaving puts loose letters back in the rack; the next visit says so once', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode(_save(version: 6, tidied: true))});
    await openVillage(tester);
    // Already tidied, so the stray Q is still on the board and no note shows.
    expect(sawNote, isFalse);
    expect((await savedJson())['boardCells'][_qCell], 'Q');

    await leave(tester);
    var json = await savedJson();
    expect((json['boardCells'] as List)[_qCell], isNull);
    expect((json['rackCells'] as List).whereType<String>().length, 10);
    expect(json['bag'], ['Q']);
    expect(json['looseNote'], 1);

    await tester.tap(find.byKey(const ValueKey('home-my-village')));
    await pumpVillage(tester);
    expect(sawNote, isTrue);
    json = await savedJson();
    expect(json['looseNote'], 0);
  });
}
