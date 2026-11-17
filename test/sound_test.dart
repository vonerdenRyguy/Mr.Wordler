import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/settings/settings_controller.dart';
import 'package:namer_app/sound/sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the game asked to play instead of playing it.
class FakeSoundBackend implements SoundBackend {
  final sfx = <Sfx>[];
  final volumes = <double>[];
  MusicTrack? playing;
  double? musicVolume;
  bool paused = false;

  @override
  void playSfx(Sfx s, double volume) {
    sfx.add(s);
    volumes.add(volume);
  }

  @override
  void playMusic(MusicTrack track, double volume) {
    playing = track;
    musicVolume = volume;
    paused = false;
  }

  @override
  void setMusicVolume(double volume) => musicVolume = volume;
  @override
  void stopMusic() => playing = null;
  @override
  void pauseMusic() => paused = true;
  @override
  void resumeMusic() => paused = false;
}

void main() {
  Future<(ProviderContainer, FakeSoundBackend)> setUp(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final fake = FakeSoundBackend();
    final c = ProviderContainer(overrides: [soundBackendProvider.overrideWithValue(fake)]);
    addTearDown(c.dispose);
    await c.read(settingsProvider.notifier).ready;
    return (c, fake);
  }

  test('music and sounds start on, fairly quiet', () async {
    final (c, _) = await setUp({});
    final s = c.read(settingsProvider);
    expect(s.musicOn, isTrue);
    expect(s.soundsOn, isTrue);
    expect(s.musicVolume, SettingsData.defaultMusicVolume);
    expect(s.soundsVolume, SettingsData.defaultSoundsVolume);
  });

  test('music and sounds settings are saved and read back', () async {
    final (c, _) = await setUp({});
    final n = c.read(settingsProvider.notifier);
    await n.setMusicOn(false);
    await n.setMusicVolume(0.25);
    await n.setSoundsOn(false);
    await n.setSoundsVolume(1.5); // clamped
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('musicOn'), isFalse);
    expect(prefs.getDouble('musicVolume'), 0.25);
    expect(prefs.getBool('soundsOn'), isFalse);
    expect(prefs.getDouble('soundsVolume'), 1.0);

    final again = SettingsController();
    await again.ready;
    expect(again.state.musicOn, isFalse);
    expect(again.state.musicVolume, 0.25);
    expect(again.state.soundsOn, isFalse);
    expect(again.state.soundsVolume, 1.0);
    again.dispose();
  });

  test('sounds play at the chosen volume, and not at all when off', () async {
    final (c, fake) = await setUp({'soundsVolume': 0.5});
    final sound = c.read(soundProvider);
    sound.play(Sfx.clack);
    expect(fake.sfx, [Sfx.clack]);
    expect(fake.volumes, [0.5]);
    await c.read(settingsProvider.notifier).setSoundsOn(false);
    sound.play(Sfx.coin);
    expect(fake.sfx, [Sfx.clack]);
  });

  test('a screen\'s music plays over the one underneath and gives it back', () async {
    final (c, fake) = await setUp({});
    final sound = c.read(soundProvider);
    sound.enterMusic(MusicTrack.village);
    expect(fake.playing, MusicTrack.village);
    sound.enterMusic(MusicTrack.daily);
    expect(fake.playing, MusicTrack.daily);
    sound.leaveMusic(MusicTrack.daily);
    expect(fake.playing, MusicTrack.village);
    sound.leaveMusic(MusicTrack.village);
    expect(fake.playing, isNull);
  });

  test('turning music off stops it; turning it on starts it again', () async {
    final (c, fake) = await setUp({});
    final sound = c.read(soundProvider);
    sound.enterMusic(MusicTrack.village);
    await c.read(settingsProvider.notifier).setMusicOn(false);
    expect(fake.playing, isNull);
    await c.read(settingsProvider.notifier).setMusicOn(true);
    expect(fake.playing, MusicTrack.village);
    await c.read(settingsProvider.notifier).setMusicVolume(0.8);
    expect(fake.musicVolume, 0.8);
  });

  test('music stays off when it was saved off', () async {
    final (c, fake) = await setUp({'musicOn': false});
    c.read(soundProvider).enterMusic(MusicTrack.timeAttack);
    expect(fake.playing, isNull);
  });
}
