// The wallpapers (spec-14): the pattern on list pages, the hills on Me and
// the start pages. SQUARE_PREVIEW=1 also writes pictures to test/preview/.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/screens/home_screen.dart';
import 'package:namer_app/screens/mode_start_pages.dart';
import 'package:namer_app/main.dart';
import 'package:namer_app/ui/wallpaper.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_test_helpers.dart';
import 'widget_test.dart' show loadAppFonts;

final _preview = Platform.environment['SQUARE_PREVIEW'] == '1';

void main() {
  setUpAll(loadAppFonts);

  Future<void> shot(WidgetTester tester, String name) async {
    if (!_preview) return;
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/$name.png'));
  }

  testWidgets('both wallpapers paint at phone and tablet sizes', (tester) async {
    for (final size in const [Size(320, 568), Size(411, 891), Size(1024, 768)]) {
      for (final kind in WallpaperKind.values) {
        await tester.pumpWidget(Center(
          child: SizedBox.fromSize(size: size, child: Wallpaper(kind: kind)),
        ));
        expect(tester.takeException(), isNull);
      }
    }
    // A slice behind a bar, top and bottom.
    for (final top in [true, false]) {
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          child: WallpaperSlice(kind: WallpaperKind.hills, top: top, child: const SizedBox(height: 80)),
        ),
      ));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Me shows the hills, Settings the pattern, Time Attack the hills', (tester) async {
    tester.view.physicalSize = const Size(411, 891);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    await skipHomeIntro();
    await tester.pumpWidget(ProviderScope(
      child: ChangeNotifierProvider(create: (_) => ThemeNotifier(), child: const MyApp()),
    ));
    await tester.pumpAndSettle();
    await goToHomePage(tester, 'Me');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byWidgetPredicate((w) => w is Wallpaper && w.kind == WallpaperKind.hills),
      findsOneWidget,
    );
    await shot(tester, 'wall_me');

    await goToHomePage(tester, 'Family');
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is Wallpaper && w.kind == WallpaperKind.pattern), findsOneWidget);
    await shot(tester, 'wall_family');

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is Wallpaper && w.kind == WallpaperKind.pattern), findsWidgets);
    await shot(tester, 'wall_settings');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await goToHomePage(tester, 'Play');
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(HomeScreen))).push(
      MaterialPageRoute<void>(builder: (_) => const TimeAttackStartPage()),
    );
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is Wallpaper && w.kind == WallpaperKind.hills), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shot(tester, 'wall_time_attack');
  });
}
