import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../players/players.dart';
import 'word_level.dart';

// Player settings: text size, reduce motion and word level. Saved in
// shared_preferences under their own keys. (Dark mode stays in
// ThemeNotifier, untouched.)

const kAppVersion = '0.0.1'; // keep in step with pubspec.yaml

class SettingsData {
  const SettingsData({
    this.textSizeStep = 0,
    this.reduceMotion = false,
    this.chosenWordLevel,
    this.showTips = true,
    this.homeIntroSeen = true,
    this.loaded = false,
    this.musicOn = true,
    this.musicVolume = defaultMusicVolume,
    this.soundsOn = true,
    this.soundsVolume = defaultSoundsVolume,
  });

  /// 0 = Normal, 1 = Large, 2 = Extra large.
  final int textSizeStep;
  final bool reduceMotion;

  /// Mr. W's tips on Home (spec-11). Per phone.
  final bool showTips;

  /// Whether this phone has seen the "swipe to look around" card
  /// (spec-11). True until the saved value is read, so it never flashes.
  final bool homeIntroSeen;

  /// True once the saved settings have been read.
  final bool loaded;

  /// Music and sounds (spec-12). Per phone; on, and fairly quiet, to start.
  final bool musicOn;
  final double musicVolume;
  final bool soundsOn;
  final double soundsVolume;

  static const defaultMusicVolume = 0.4;
  static const defaultSoundsVolume = 0.7;

  /// The word level the player picked (spec-06); null until they pick one.
  final WordLevel? chosenWordLevel;

  /// The level in use: Wordsmith (the puzzle as it always was) until the
  /// player picks another.
  WordLevel get wordLevel => chosenWordLevel ?? WordLevel.wordsmith;

  static const textSizeLabels = ['Normal', 'Large', 'Extra large'];
  static const _textScales = [1.0, 1.15, 1.3];

  /// What the phone's text scale is multiplied by.
  double get textScale => _textScales[textSizeStep];

  SettingsData copyWith({
    int? textSizeStep,
    bool? reduceMotion,
    WordLevel? chosenWordLevel,
    bool? showTips,
    bool? homeIntroSeen,
    bool? musicOn,
    double? musicVolume,
    bool? soundsOn,
    double? soundsVolume,
  }) =>
      SettingsData(
        textSizeStep: textSizeStep ?? this.textSizeStep,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        chosenWordLevel: chosenWordLevel ?? this.chosenWordLevel,
        showTips: showTips ?? this.showTips,
        homeIntroSeen: homeIntroSeen ?? this.homeIntroSeen,
        loaded: loaded,
        musicOn: musicOn ?? this.musicOn,
        musicVolume: musicVolume ?? this.musicVolume,
        soundsOn: soundsOn ?? this.soundsOn,
        soundsVolume: soundsVolume ?? this.soundsVolume,
      );
}

class SettingsController extends StateNotifier<SettingsData> {
  SettingsController() : super(const SettingsData()) {
    _ready = _load();
  }

  static const textSizeKey = 'textSizeStep';
  static const reduceMotionKey = 'reduceMotion';
  static const wordLevelKey = 'wordLevel';
  static const showTipsKey = 'showTips';
  static const homeIntroSeenKey = 'homeIntroSeen';
  static const musicOnKey = 'musicOn';
  static const musicVolumeKey = 'musicVolume';
  static const soundsOnKey = 'soundsOn';
  static const soundsVolumeKey = 'soundsVolume';

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
      showTips: prefs.getBool(showTipsKey) ?? true,
      homeIntroSeen: prefs.getBool(homeIntroSeenKey) ?? false,
      loaded: true,
      musicOn: prefs.getBool(musicOnKey) ?? true,
      musicVolume: (prefs.getDouble(musicVolumeKey) ?? SettingsData.defaultMusicVolume).clamp(0.0, 1.0),
      soundsOn: prefs.getBool(soundsOnKey) ?? true,
      soundsVolume: (prefs.getDouble(soundsVolumeKey) ?? SettingsData.defaultSoundsVolume).clamp(0.0, 1.0),
    );
  }

  Future<void> setShowTips(bool value) async {
    state = state.copyWith(showTips: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(showTipsKey, value);
  }

  Future<void> markHomeIntroSeen() async {
    state = state.copyWith(homeIntroSeen: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(homeIntroSeenKey, true);
  }

  Future<void> setMusicOn(bool value) async {
    state = state.copyWith(musicOn: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(musicOnKey, value);
  }

  Future<void> setMusicVolume(double value) async {
    state = state.copyWith(musicVolume: value.clamp(0.0, 1.0));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(musicVolumeKey, state.musicVolume);
  }

  Future<void> setSoundsOn(bool value) async {
    state = state.copyWith(soundsOn: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(soundsOnKey, value);
  }

  Future<void> setSoundsVolume(double value) async {
    state = state.copyWith(soundsVolume: value.clamp(0.0, 1.0));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(soundsVolumeKey, state.soundsVolume);
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
