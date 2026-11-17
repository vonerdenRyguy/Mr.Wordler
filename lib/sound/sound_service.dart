import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_controller.dart';

// Sounds and music (spec-12). Every sound is a short file in assets/sounds/
// made by tool/make_sounds.dart. Sound is always extra: a sound that fails
// to play is silent, never an error, and nothing in the game is sound-only.

enum Sfx {
  tap('tap'),
  clack('clack'),
  word('word'),
  magic('magic'),
  coin('coin'),
  whoosh('whoosh'),
  reward('reward'),
  building('building');

  const Sfx(this.file);
  final String file;
}

enum MusicTrack {
  village('music_village'),
  daily('music_daily'),
  timeAttack('music_time_attack');

  const MusicTrack(this.file);
  final String file;
}

/// What actually makes the noise. Tests use a fake that records instead.
abstract class SoundBackend {
  void playSfx(Sfx sfx, double volume);
  void playMusic(MusicTrack track, double volume);
  void setMusicVolume(double volume);
  void stopMusic();
  void pauseMusic();
  void resumeMusic();
}

/// Plays nothing: used under `flutter test`, where there's no audio plugin.
class SilentSoundBackend implements SoundBackend {
  const SilentSoundBackend();
  @override
  void playSfx(Sfx sfx, double volume) {}
  @override
  void playMusic(MusicTrack track, double volume) {}
  @override
  void setMusicVolume(double volume) {}
  @override
  void stopMusic() {}
  @override
  void pauseMusic() {}
  @override
  void resumeMusic() {}
}

/// The real thing, through audioplayers. Mixes with whatever else the
/// phone is playing (it never stops someone's podcast).
class AudioSoundBackend implements SoundBackend {
  AudioSoundBackend() {
    _quietly(() => AudioPlayer.global.setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        )));
  }

  // A few players per sound so quick repeats (tiles!) overlap.
  static const _perSfx = 3;
  final _sfx = <Sfx, List<AudioPlayer>>{};
  final _next = <Sfx, int>{};
  AudioPlayer? _music;
  MusicTrack? _track;

  static void _quietly(Future<void> Function() f) {
    try {
      unawaited(f().catchError((Object _) {}));
    } catch (_) {
      // No sound this time.
    }
  }

  @override
  void playSfx(Sfx sfx, double volume) {
    final players = _sfx.putIfAbsent(sfx, () => [for (int i = 0; i < _perSfx; i++) AudioPlayer()]);
    final i = _next[sfx] ?? 0;
    _next[sfx] = (i + 1) % _perSfx;
    final p = players[i];
    _quietly(() => p.play(AssetSource('sounds/${sfx.file}.wav'), volume: volume, mode: PlayerMode.lowLatency));
  }

  @override
  void playMusic(MusicTrack track, double volume) {
    final player = _music ??= AudioPlayer();
    if (_track == track) {
      _quietly(() => player.setVolume(volume));
      if (player.state != PlayerState.playing) _quietly(player.resume);
      return;
    }
    _track = track;
    _quietly(() async {
      await player.stop();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('sounds/${track.file}.wav'), volume: volume);
    });
  }

  @override
  void setMusicVolume(double volume) {
    final player = _music;
    if (player != null) _quietly(() => player.setVolume(volume));
  }

  @override
  void stopMusic() {
    _track = null;
    final player = _music;
    if (player != null) _quietly(player.stop);
  }

  @override
  void pauseMusic() {
    final player = _music;
    if (player != null && _track != null) _quietly(player.pause);
  }

  @override
  void resumeMusic() {
    final player = _music;
    if (player != null && _track != null) _quietly(player.resume);
  }
}

bool get _underTest => Platform.environment.containsKey('FLUTTER_TEST');

final soundBackendProvider = Provider<SoundBackend>(
  (ref) => _underTest ? const SilentSoundBackend() : AudioSoundBackend(),
);

/// What the game calls: plays sounds and music as the settings allow.
class SoundController {
  SoundController(this._ref) {
    // A change in Settings applies straight away.
    _ref.listen<SettingsData>(settingsProvider, (prev, next) {
      if (prev?.musicOn != next.musicOn || prev?.musicVolume != next.musicVolume) _applyMusic();
    });
  }

  final Ref _ref;
  final _stack = <MusicTrack>[];

  SoundBackend get _backend => _ref.read(soundBackendProvider);
  SettingsData get _settings => _ref.read(settingsProvider);

  void play(Sfx sfx) {
    final s = _settings;
    if (!s.soundsOn || s.soundsVolume <= 0) return;
    _backend.playSfx(sfx, s.soundsVolume);
  }

  /// Starts [track] (a screen calls this when it opens) until [leaveMusic].
  void enterMusic(MusicTrack track) {
    _stack.add(track);
    _applyMusic();
  }

  void leaveMusic(MusicTrack track) {
    final i = _stack.lastIndexOf(track);
    if (i >= 0) _stack.removeAt(i);
    _applyMusic();
  }

  MusicTrack? get currentTrack => _stack.isEmpty ? null : _stack.last;

  void _applyMusic() {
    final s = _settings;
    final track = currentTrack;
    if (track == null || !s.musicOn || s.musicVolume <= 0) {
      _backend.stopMusic();
    } else {
      _backend.playMusic(track, s.musicVolume);
    }
  }

  void pause() => _backend.pauseMusic();
  void resume() => _backend.resumeMusic();
}

final soundProvider = Provider<SoundController>((ref) => SoundController(ref));

/// Plays [track] while this widget is on screen; the screen underneath gets
/// its music back when this one closes.
class MusicScope extends ConsumerStatefulWidget {
  const MusicScope({super.key, required this.track, required this.child});

  final MusicTrack track;
  final Widget child;

  @override
  ConsumerState<MusicScope> createState() => _MusicScopeState();
}

class _MusicScopeState extends ConsumerState<MusicScope> {
  late final SoundController _sound;

  @override
  void initState() {
    super.initState();
    _sound = ref.read(soundProvider);
    _sound.enterMusic(widget.track);
  }

  @override
  void dispose() {
    _sound.leaveMusic(widget.track);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Pauses the music while the app is in the background.
class SoundLifecycle extends ConsumerStatefulWidget {
  const SoundLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SoundLifecycle> createState() => _SoundLifecycleState();
}

class _SoundLifecycleState extends ConsumerState<SoundLifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sound = ref.read(soundProvider);
    if (state == AppLifecycleState.resumed) {
      sound.resume();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      sound.pause();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
