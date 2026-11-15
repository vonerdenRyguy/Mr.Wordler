import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../players/players.dart';
import 'word_level.dart';

// Player settings: text size, reduce motion and word level. Saved in
// shared_preferences under their own keys. (Dark mode stays in
// ThemeNotifier, untouched.)

const kAppVersion = '0.0.1'; // keep in step with pubspec.yaml

class SettingsData {
  const SettingsData({this.textSizeStep = 0, this.reduceMotion = false, this.chosenWordLevel});

  /// 0 = Normal, 1 = Large, 2 = Extra large.
  final int textSizeStep;
  final bool reduceMotion;

  /// The word level the player picked (spec-06); null until they pick one.
  final WordLevel? chosenWordLevel;

  /// The level in use: Wordsmith (the puzzle as it always was) until the
  /// player picks another.
  WordLevel get wordLevel => chosenWordLevel ?? WordLevel.wordsmith;

  static const textSizeLabels = ['Normal', 'Large', 'Extra large'];
  static const _textScales = [1.0, 1.15, 1.3];

  /// What the phone's text scale is multiplied by.
  double get textScale => _textScales[textSizeStep];

  SettingsData copyWith({int? textSizeStep, bool? reduceMotion, WordLevel? chosenWordLevel}) => SettingsData(
        textSizeStep: textSizeStep ?? this.textSizeStep,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        chosenWordLevel: chosenWordLevel ?? this.chosenWordLevel,
      );
}

class SettingsController extends StateNotifier<SettingsData> {
  SettingsController() : super(const SettingsData()) {
    _ready = _load();
  }

  static const textSizeKey = 'textSizeStep';
  static const reduceMotionKey = 'reduceMotion';
  static const wordLevelKey = 'wordLevel';

  // The word level is per player (spec-07); text size and Reduce motion
  // belong to the phone.
  final String _wordLevelKey = PlayerKeys.of(wordLevelKey);

  late final Future<void> _ready;

  /// Completes once saved settings have been read.
  Future<void> get ready => _ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = SettingsData(
      textSizeStep: (prefs.getInt(textSizeKey) ?? 0).clamp(0, 2),
      reduceMotion: prefs.getBool(reduceMotionKey) ?? false,
      // Keep a level picked while this was loading.
      chosenWordLevel: state.chosenWordLevel ?? wordLevelFromName(prefs.getString(_wordLevelKey)),
    );
  }

  Future<void> setWordLevel(WordLevel level) async {
    state = state.copyWith(chosenWordLevel: level);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wordLevelKey, level.name);
  }

  Future<void> setTextSizeStep(int step) async {
    state = state.copyWith(textSizeStep: step.clamp(0, 2));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(textSizeKey, state.textSizeStep);
  }

  Future<void> setReduceMotion(bool value) async {
    state = state.copyWith(reduceMotion: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(reduceMotionKey, value);
  }
}

final settingsProvider = StateNotifierProvider<SettingsController, SettingsData>((ref) {
  ref.watch(currentPlayerIdProvider);
  return SettingsController();
});
