import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// The one place every color, text style, size and radius in the app comes
// from (spec-03). Screens use these instead of Material's named colors, so
// the whole app keeps one look: warm paper, dark ink outlines, and chunky
// buttons and tiles with a solid bottom lip.

class WColors {
  WColors._();

  static const paper = Color(0xFFF3EAD6); // every screen's background
  static const card = Color(0xFFFFF6E0); // cards, chips, secondary buttons, dialogs
  static const ink = Color(0xFF3B2A1E); // main text, outlines, button lips
  static const muted = Color(0xFF6B5A48); // small and secondary text
  static const tile = Color(0xFFF3E3C3); // letter tile face
  static const tileGlow = Color(0xFFFFF3C4); // tiles in a just-made word
  static const grass = Color(0xFF2F7A22); // main action buttons
  static const grassLip = Color(0xFF1E5216);
  static const sun = Color(0xFFF6C443); // selected state, glow, coins, level
  static const sky = Color(0xFF4DB6EC); // Daily, Well
  static const skyTint = Color(0xFFCDEBFA);
  static const coral = Color(0xFFF59C86); // Time Attack
  static const coralTint = Color(0xFFFCE1D9);
  static const lilac = Color(0xFFC9B3F0); // Theme Rush
  static const lilacTint = Color(0xFFEDE5FB);
  static const leaf = Color(0xFF8ACD52); // Village, Farm
  static const leafTint = Color(0xFFDCEFC8);
  static const soil = Color(0xFF6B4A2B); // rack background, toggle track
  static const soilDeep = Color(0xFF5A3D22); // empty rack slot
  static const wood = Color(0xFF8A5A30); // board frame
  static const boardBed = Color(0xFFC9A978); // behind the board cells
  static const boardCell = Color(0xFFE3D3B0); // empty board cell, disabled fill
  static const grassField = Color(0xFF9BC86B); // Estate board background
  static const grassFieldCell = Color(0xFFAED47E); // empty Estate cell
  static const brick = Color(0xFFC8432F); // End, Leave, Give up
  static const white = Color(0xFFFFFFFF);
}

/// Each mode's own color: its icon tile, start page hero, and timer pill.
class WModeColors {
  WModeColors._();

  static const freePlay = WColors.tile;
  static const daily = WColors.sky;
  static const timeAttack = WColors.coral;
  static const themeRush = WColors.lilac;
  static const village = WColors.leaf;
}

class WFonts {
  WFonts._();

  static const display = 'LilitaOne'; // titles, buttons, numbers, tiles
  static const body = 'Atkinson'; // everything else
}

class WText {
  WText._();

  static const title = TextStyle(fontFamily: WFonts.display, fontSize: 40, color: WColors.ink, height: 1.1);
  static const heading = TextStyle(fontFamily: WFonts.display, fontSize: 26, color: WColors.ink, height: 1.15);
  static const buttonBig = TextStyle(fontFamily: WFonts.display, fontSize: 22, height: 1.1);
  static const button = TextStyle(fontFamily: WFonts.display, fontSize: 19, height: 1.1);
  static const buttonSmall = TextStyle(fontFamily: WFonts.display, fontSize: 17, height: 1.1);
  static const number = TextStyle(fontFamily: WFonts.display, fontSize: 28, color: WColors.ink, height: 1.0);
  static const bodyBold = TextStyle(fontFamily: WFonts.body, fontSize: 18, fontWeight: FontWeight.w700, color: WColors.ink);
  static const body = TextStyle(fontFamily: WFonts.body, fontSize: 17, fontWeight: FontWeight.w400, color: WColors.ink);
  // Nothing in the app is smaller than this.
  static const label = TextStyle(fontFamily: WFonts.body, fontSize: 14, fontWeight: FontWeight.w700, color: WColors.muted);
}

class WSize {
  WSize._();

  static const outline = 3.0; // buttons and cards
  static const outlineSmall = 2.0; // chips and small tiles
  static const lip = 4.0;
  static const lipHero = 5.0;
  static const lipSmall = 3.0;
  static const radiusButton = 16.0;
  static const radiusCard = 20.0;
  static const radiusHero = 22.0;
  static const radiusChip = 22.0;
  static const gap1 = 4.0;
  static const gap2 = 8.0;
  static const gap3 = 12.0;
  static const gap4 = 16.0;
  static const gap5 = 24.0;
  static const screenPadding = 16.0;
  static const gamePadding = 12.0;
  static const tapTarget = 48.0;
  static const chipHeight = 44.0;
}

/// A solid bottom shadow with no blur: the "lip" every chunky thing has.
List<BoxShadow> wLip(double height, {Color color = WColors.ink}) =>
    [BoxShadow(color: color, offset: Offset(0, height), blurRadius: 0)];

/// The app's one ThemeData, built from the tokens. Light only for now; a
/// dark palette is a later spec, so darkTheme points here too.
ThemeData buildWordlerTheme() {
  const scheme = ColorScheme.light(
    primary: WColors.grass,
    onPrimary: WColors.white,
    secondary: WColors.sun,
    onSecondary: WColors.ink,
    surface: WColors.card,
    onSurface: WColors.ink,
    error: WColors.brick,
    onError: WColors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: WColors.paper,
    canvasColor: WColors.paper,
    fontFamily: WFonts.body,
    textTheme: const TextTheme(
      bodyLarge: WText.body,
      bodyMedium: WText.body,
      bodySmall: WText.label,
      titleLarge: WText.heading,
      titleMedium: WText.bodyBold,
      labelLarge: WText.button,
    ),
    dialogTheme: DialogTheme(
      backgroundColor: WColors.card,
      titleTextStyle: WText.heading,
      contentTextStyle: WText.body,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WSize.radiusHero),
        side: const BorderSide(color: WColors.ink, width: WSize.outline),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: WColors.ink,
      contentTextStyle: TextStyle(fontFamily: WFonts.body, fontSize: 16, color: WColors.card),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? WColors.white : WColors.card),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? WColors.grass : WColors.boardCell),
      trackOutlineColor: WidgetStateProperty.all(WColors.ink),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: WColors.grass,
      linearTrackColor: WColors.boardCell,
    ),
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: wordlerOverlayStyle,
    ),
  );
}

/// Dark status bar icons on paper, and a paper navigation bar.
const wordlerOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: WColors.paper,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: WColors.paper,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// WCAG 2 contrast ratio between two opaque colors (1.0 to 21.0).
double contrastRatio(Color a, Color b) {
  double channel(int c) {
    final s = c / 255.0;
    return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  double luminance(Color c) =>
      0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue);
  final la = luminance(a);
  final lb = luminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}
