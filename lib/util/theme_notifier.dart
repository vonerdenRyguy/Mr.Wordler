import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Holds the app's dark-mode preference and persists it via SharedPreferences
// so the Settings screen's toggle survives an app restart.
class ThemeNotifier extends ChangeNotifier {
  bool isDarkMode = false;

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode = prefs.getBool('isDarkMode') ?? false;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    isDarkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }
}
