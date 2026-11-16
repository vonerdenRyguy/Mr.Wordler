import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home's first-time "swipe to look around" card covers the page; tests
/// that aren't about it say it has been seen. Call after
/// `setMockInitialValues` and before pumping the app.
Future<void> skipHomeIntro() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(SettingsController.homeIntroSeenKey, true);
}

/// Home's pages, by the tab that opens them.
Future<void> goToHomePage(WidgetTester tester, String tab) async {
  // The tab bar is drawn after the pages, so its label is the last match.
  await tester.tap(find.text(tab).last);
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
