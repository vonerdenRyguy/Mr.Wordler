import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

// "Hear the word" (spec-06): reads a word aloud with the phone's own
// voice, so it works with no network. Slowed a little for young readers.
// If the phone has no voice installed nothing is said; that is never an
// error the player sees.
class WordSpeaker {
  FlutterTts? _tts;

  Future<void> speak(String word) async {
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setSpeechRate(0.4);
      await tts.stop();
      await tts.speak(word.toLowerCase());
    } catch (_) {
      // No voice engine, or the plugin isn't available on this platform.
    }
  }
}

/// Overridable in tests.
final wordSpeakerProvider = Provider<WordSpeaker>((ref) => WordSpeaker());
