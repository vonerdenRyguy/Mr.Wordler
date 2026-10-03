import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Player settings: text size and reduce motion. Saved in
// shared_preferences under their own keys. (Dark mode stays in
// ThemeNotifier, untouched.)

const kAppVersion = '0.0.1'; // keep in step with pubspec.yaml

class SettingsData {
  const SettingsData({this.textSizeStep = 0, this.reduceMotion = false});

  /// 0 = Normal, 1 = Large, 2 = Extra large.
  final int textSizeStep;
  final bool reduceMotion;

  static const textSizeLabels = ['Normal', 'Large', 'Extra large'];
  static const _textScales = [1.0, 1.15, 1.3];

  /// What the phone's text scale is multiplied by.
  double get textScale => _textScales[textSizeStep];

  SettingsData copyWith({int? textSizeStep, bool? reduceMotion}) => SettingsData(
        textSizeStep: textSizeStep ?? this.textSizeStep,
        reduceMotion: reduceMotion ?? this.reduceMotion,
      );
}

class SettingsController extends StateNotifier<SettingsData> {
  SettingsController() : super(const SettingsData()) {
    _ready = _load();
  }

  static const textSizeKey = 'textSizeStep';
  static const reduceMotionKey = 'reduceMotion';

  late final Future<void> _ready;

  /// Completes once saved settings have been read.
  Future<void> get ready => _ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = SettingsData(
      textSizeStep: (prefs.getInt(textSizeKey) ?? 0).clamp(0, 2),
      reduceMotion: prefs.getBool(reduceMotionKey) ?? false,
    );
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

final settingsProvider = StateNotifierProvider<SettingsController, SettingsData>((ref) => SettingsController());
