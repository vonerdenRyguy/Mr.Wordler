import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sound/sound_service.dart';
import '../village/magic_word.dart';
import 'word_landing.dart';

/// An extra note the banner adds after a word, e.g. "HORSE · Secret word!".
/// Returns null for an ordinary word (the default for every word). A mode
/// overrides this in its own ProviderScope.
final landingNoteProvider = Provider<String? Function(String word)>((ref) => (_) => null);

const _bannerMs = 1400;
const _inMs = 200;
const _outMs = 300;

/// The word(s) a landed tile just made, shown big over the top of the
/// board for a moment. Sits outside the board's zoom so it's always full
/// size, and never blocks a drag.
class WordLandingBanner extends ConsumerStatefulWidget {
  const WordLandingBanner({super.key});

  @override
  ConsumerState<WordLandingBanner> createState() => _WordLandingBannerState();
}

class _WordLandingBannerState extends ConsumerState<WordLandingBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  String? _text;
  int _lastSeq = -1;
  int _lastClackSeq = -1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: _bannerMs))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) setState(() => _text = null);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TileLanding?>(tileLandingProvider, (prev, next) {
      if (next == null) return;
      final sound = ref.read(soundProvider);
      // Every tile that lands clacks (spec-12); a word chimes, a magic
      // word chimes brighter.
      if (next.words.isEmpty) {
        if (next.seq != _lastClackSeq) {
          _lastClackSeq = next.seq;
          sound.play(Sfx.clack);
        }
        return;
      }
      if (next.seq == _lastSeq) return;
      _lastSeq = next.seq;
      sound.play(next.words.any((w) => magicWordFor(w.word) != null) ? Sfx.magic : Sfx.word);
      final noteFor = ref.read(landingNoteProvider);
      setState(() => _text = next.words.map((w) {
            final note = noteFor(w.word);
            return note == null ? w.word : '${w.word} · $note';
          }).join(' · '));
      HapticFeedback.lightImpact();
      _controller.forward(from: 0);
    });

    final text = _text;
    if (text == null) return const SizedBox.shrink();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final ms = _controller.value * _bannerMs;
            final fadeIn = (ms / _inMs).clamp(0.0, 1.0);
            final fadeOut = ((_bannerMs - ms) / _outMs).clamp(0.0, 1.0);
            final opacity = reduceMotion ? 1.0 : (fadeIn < 1 ? fadeIn : fadeOut);
            final slide = reduceMotion ? 0.0 : -12 * (1 - Curves.easeOut.transform(fadeIn));
            return Opacity(
              opacity: opacity,
              child: Transform.translate(offset: Offset(0, slide), child: child),
            );
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E0),
              border: Border.all(color: const Color(0xFF3B2A1E), width: 3),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Color(0xFF3B2A1E), offset: Offset(0, 4), blurRadius: 0)],
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'LilitaOne',
                fontSize: 26,
                letterSpacing: 1.5,
                color: Color(0xFF3B2A1E),
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
