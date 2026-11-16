import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ChangeNotifierProvider is defined by both riverpod and provider; this
// app uses provider's version for ThemeNotifier, so hide riverpod's.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:namer_app/online/family_online_controller.dart';
import 'package:namer_app/online/firebase_family_backend.dart';
import 'package:namer_app/players/family_widgets.dart';
import 'package:namer_app/players/players.dart';
import 'package:namer_app/screens/home_screen.dart';
import 'package:namer_app/screens/players_screens.dart';
import 'package:namer_app/settings/settings_controller.dart';
import 'package:namer_app/ui/tokens.dart';
import 'package:namer_app/util/theme_notifier.dart';
import 'package:provider/provider.dart' hide Consumer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(wordlerOverlayStyle);
  final themeNotifier = ThemeNotifier();
  await themeNotifier.loadFromPrefs();
  // Family online (spec-08). A build made without google-services.json
  // can't start Firebase; the app then works as before, offline.
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase not available: $e');
  }
  final container = ProviderContainer();
  if (firebaseReady) _listenForSignInLinks(container);
  runApp(
    // ProviderScope hosts the Riverpod state used by the game-mode engine
    // and the Portfolio/XP meta-layer. ThemeNotifier stays on `provider`
    // (already working, out of scope to migrate) -- the two coexist fine.
    UncontrolledProviderScope(
      container: container,
      child: ChangeNotifierProvider.value(
        value: themeNotifier,
        child: const MyApp(),
      ),
    ),
  );
}

/// Emailed sign-in links open the app; hand each one to whoever is
/// holding the phone (the player who asked for it).
void _listenForSignInLinks(ProviderContainer container) {
  final links = AppLinks();
  Future<void> handle(Uri uri) async {
    try {
      await container.read(familyOnlineProvider.notifier).handleLink(uri.toString());
    } catch (e) {
      debugPrint('Sign-in link failed: $e');
    }
  }

  links.getInitialLink().then((uri) {
    if (uri != null) handle(uri);
  });
  links.uriLinkStream.listen(handle);
}

final wordlerTheme = buildWordlerTheme();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    return MaterialApp(
      title: 'Mr. Wordler',
      // One light theme built from the design tokens (lib/ui/tokens.dart).
      // A proper dark palette is a later spec, so dark mode points at the
      // same theme for now; ThemeNotifier's saved value is kept as is.
      theme: wordlerTheme,
      darkTheme: wordlerTheme,
      themeMode: themeNotifier.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => Consumer(builder: (context, ref, _) {
        // The phone's text size times the in-app Text size setting,
        // clamped so nothing gets silly. Tiles draw their letters at a
        // fixed size, so the board and rack always fit. Reduce motion
        // is on if either the phone or the app setting asks for it.
        final settings = ref.watch(settingsProvider);
        final mediaQuery = MediaQuery.of(context);
        final scale = (mediaQuery.textScaler.scale(1.0) * settings.textScale).clamp(0.8, 1.6);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: mediaQuery.disableAnimations || settings.reduceMotion,
          ),
          child: child!,
        );
      }),
      home: const AppRoot(),
    );
  }
}

/// The first screen: Home, or "Who's playing?" when two or more players
/// share this phone and nobody has said who is holding it yet.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFamily = ref.watch(playersProvider.select((s) => s.isFamily));
    final picked = ref.watch(playerPickedProvider);
    if (isFamily && !picked) return const WhoIsPlayingScreen();
    // Keyed by player so Home starts afresh when the phone changes hands.
    return HomeScreen(key: ValueKey(ref.watch(currentPlayerIdProvider)));
  }
}
