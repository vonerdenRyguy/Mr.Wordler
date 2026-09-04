import 'package:flutter/material.dart';
// ChangeNotifierProvider is defined by both riverpod and provider; this
// app uses provider's version for ThemeNotifier, so hide riverpod's.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:namer_app/screens/menu_screen.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeNotifier = ThemeNotifier();
  await themeNotifier.loadFromPrefs();
  runApp(
    // ProviderScope hosts the Riverpod state used by the game-mode engine
    // and the Portfolio/XP meta-layer. ThemeNotifier stays on `provider`
    // (already working, out of scope to migrate) -- the two coexist fine.
    ProviderScope(
      child: ChangeNotifierProvider.value(
        value: themeNotifier,
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    return MaterialApp(
      title: 'Bananagrams',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: themeNotifier.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        // Clamp the OS font-scale setting so a phone with "large text"
        // accessibility settings enabled doesn't blow out the tightly
        // packed letter grid; the game already scales its own tile text
        // to the screen size, so this only guards against extreme cases.
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: mediaQuery.textScaler.clamp(
              minScaleFactor: 0.8,
              maxScaleFactor: 1.2,
            ),
          ),
          child: child!,
        );
      },
      home: const MenuScreen(),
    );
  }
}
