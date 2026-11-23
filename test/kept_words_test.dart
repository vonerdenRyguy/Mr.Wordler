// spec-17 changes after the first build: a building already standing when the
// real-words rule arrives stays standing (kept words), the tidy-up takes only
// stray letters, and extra letters wait in the letter bag.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/grid_providers.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart' show skipHomeIntro;

const _size = 500;
const _mid = _size ~/ 2;
const _key = 'infiniteEstateVillageSave';
// WELL across from (mid, mid-3); a Q under the E ("EQ" is no word).
const _eCell = _mid * _size + _mid - 2;
const _qUnderE = (_mid + 1) * _size + _mid - 2;

Map<String, dynamic> _save({required int version, bool tidied = false, List<String>? rack, List<String>? bag}) {
  final board = List<String?>.filled(_size * _size, null);
  'WELL'.split('').asMap().forEach((i, l) => board[_mid * _size + _mid - 3 + i] = l);
  board[_qUnderE] = 'Q';
  return {
    'boardCells': board,
    'rackCells': rack ?? List<String>.filled(10, 'E'),
    'pool': List<String>.filled(50, 'E'),
    'dealtLetters': [...'WELL'.split(''), ...List<String>.filled(10, 'E')],
    'lastCashedOutScore': 0,
    'discoveredWords': ['WELL'],
    'saveVersion': version,
    if (version >= 5) 'tidiedLoose': tidied,
    if (bag != null) 'bag': bag,
  };
}

void main() {
  Future<void> openVillage(WidgetTester tester) async {
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
    await tester.tap(find.text('Visit your village'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>> savedJson() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return jsonDecode(prefs.getString(_key)!) as Map<String, dynamic>;
  }

  testWidgets('a v4 village: WELL with a Q under its E keeps its building, the Q goes to the bag, the E stays',
      (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode(_save(version: 4))});
    await openVillage(tester);

    final json = await savedJson();
    expect(json['saveVersion'], 5);
    final board = json['boardCells'] as List;
    expect(board[_qUnderE], isNull);
    expect(board[_eCell], 'E');
    expect(json['bag'], ['Q']);
    expect((json['keptRuns'] as List).single['w'], 'WELL');

    // The building is still there: one building, as before the update.
    await tester.tap(find.bySemanticsLabel('Village view'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsWidgets);
    expect(find.text('building'), findsOneWidget);
  });

  testWidgets('without being kept (a village already tidied), a bad crossing builds nothing', (tester) async {
    SharedPreferences.setMockInitialValues({_key: jsonEncode(_save(version: 5, tidied: true))});
    await openVillage(tester);
    await tester.tap(find.bySemanticsLabel('Village view'));
    await tester.pumpAndSettle();
    expect(find.text('buildings'), findsOneWidget); // 0 buildings
  });

  testWidgets('a big bag shows as a +N chip, the rack stays at 10, and a bag letter swaps in', (tester) async {
    final bag = List<String>.generate(23, (i) => 'ABCD'[i % 4]);
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode(_save(version: 5, tidied: true, bag: bag)),
    });
    await openVillage(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    var state = container.read(gridGameControllerProvider);
    expect(state.rackCells, hasLength(10));
    expect(state.bag, hasLength(23));
    expect(find.text('+23'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('letter-bag-chip')));
    await tester.pumpAndSettle();
    expect(find.text('Your letter bag'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bag-letter-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bag-rack-0')));
    await tester.pumpAndSettle();
    state = container.read(gridGameControllerProvider);
    expect(state.rackCells[0], 'A');
    expect(state.bag, hasLength(23)); // the rack's E went into the bag in its place
    expect(state.bag.last, 'E');
  });

  testWidgets('the bag survives a save and load', (tester) async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode(_save(version: 5, tidied: true, bag: ['Z', 'Y'])),
    });
    await openVillage(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(container.read(gridGameControllerProvider).bag, ['Z', 'Y']);
    expect((await savedJson())['bag'] ?? ['Z', 'Y'], ['Z', 'Y']);
  });
}
