// Writes a picture of the Village view to test/preview/ when run with
// SQUARE_PREVIEW=1 (for looking at the buildings; not a real check).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/game/word_landing.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:namer_app/village/iso_village_view.dart';
import 'package:namer_app/village/village_art.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show loadAppFonts;

const _size = 500;
const _mid = _size ~/ 2;
int _idx(int r, int c) => r * _size + c;

void main() {
  final preview = Platform.environment['SQUARE_PREVIEW'] == '1';
  setUpAll(loadAppFonts);

  testWidgets('village preview', (tester) async {
    final board = List<String?>.filled(_size * _size, null);
    void across(int r, int c, String w) => w.split('').asMap().forEach((i, l) => board[_idx(r, c + i)] = l);
    void down(int r, int c, String w) => w.split('').asMap().forEach((i, l) => board[_idx(r + i, c)] = l);
    across(_mid, _mid - 2, 'HOUSE');
    down(_mid - 1, _mid - 1, 'TOWER');
    across(_mid + 3, _mid - 3, 'FARM');
    down(_mid, _mid + 2, 'EAR');
    across(_mid - 3, _mid + 1, 'MILL');
    across(_mid + 6, _mid - 5, 'GARDEN');
    across(_mid - 7, _mid - 4, 'BRIDGE');
    down(_mid - 6, _mid + 5, 'WELL');
    down(_mid + 4, _mid + 3, 'BARN');
    SharedPreferences.setMockInitialValues({
      'homeIntroSeen': true,
      'infiniteEstateVillageSave': jsonEncode({
        'boardCells': board,
        'rackCells': List<String>.filled(10, 'E'),
        'pool': List<String>.filled(50, 'E'),
        'dealtLetters': List<String>.filled(30, 'E'),
        'lastCashedOutScore': 0,
        'discoveredWords': ['HOUSE', 'TOWER', 'FARM', 'MILL', 'GARDEN', 'BRIDGE', 'WELL', 'BARN'],
        'saveVersion': 2,
      }),
    });
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => VillageArt.load());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wordCheckProvider.overrideWithValue(
            (w) async => {'HOUSE', 'TOWER', 'FARM', 'MILL', 'EAR', 'GARDEN', 'BRIDGE', 'WELL', 'BARN'}.contains(w)),
      ],
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-my-village')));
    await tester.pumpAndSettle();
    if (find.bySemanticsLabel('Village view').evaluate().isNotEmpty) {
      await tester.tap(find.bySemanticsLabel('Village view'));
    }
    await tester.pumpAndSettle();
    // Sprites decode for real.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    expect(find.byType(IsoVillageView), findsOneWidget);
    if (preview) {
      await expectLater(find.byType(IsoVillageView), matchesGoldenFile('preview/village.png'));
    }
  }, skip: !Platform.environment.containsKey('SQUARE_PREVIEW'));
}
