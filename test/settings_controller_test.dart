import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults are Normal text and motion on', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController();
    await controller.ready;
    expect(controller.state.textSizeStep, 0);
    expect(controller.state.textScale, 1.0);
    expect(controller.state.reduceMotion, isFalse);
  });

  test('text size and reduce motion save and load', () async {
    SharedPreferences.setMockInitialValues({});
    final first = SettingsController();
    await first.ready;
    await first.setTextSizeStep(2);
    await first.setReduceMotion(true);

    final second = SettingsController();
    await second.ready;
    expect(second.state.textSizeStep, 2);
    expect(second.state.textScale, 1.3);
    expect(second.state.reduceMotion, isTrue);
  });
}
