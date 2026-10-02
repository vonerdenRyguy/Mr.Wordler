import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/screens/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Stats lists Free Play top times, fastest first', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'leaderboardEntries': [
        jsonEncode({'name': 'Slow', 'time': 300, 'displayTime': '05:00'}),
        jsonEncode({'name': 'Ryan', 'time': 142, 'displayTime': '02:22'}),
      ],
    });

    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: StatsScreen())));
    await tester.pumpAndSettle();

    expect(find.text('Free Play top times'), findsOneWidget);
    final first = tester.getTopLeft(find.text('1. Ryan'));
    final second = tester.getTopLeft(find.text('2. Slow'));
    expect(first.dy, lessThan(second.dy));
    expect(find.text('02:22'), findsOneWidget);
    expect(find.text('No wins yet'), findsNothing);
  });

  testWidgets('Stats says "No wins yet" with an empty leaderboard', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: StatsScreen())));
    await tester.pumpAndSettle();

    expect(find.text('No wins yet'), findsOneWidget);
  });

  test('lib/ uses no old named colors (one look: design tokens only)', () {
    final banned = RegExp(r'Colors\.(deepPurple|orangeAccent|greenAccent)\b');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (banned.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
