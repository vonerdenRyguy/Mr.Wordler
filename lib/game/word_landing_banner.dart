import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'word_landing.dart';

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
      if (next == null || next.words.isEmpty || next.seq == _lastSeq) return;
      _lastSeq = next.seq;
      setState(() => _text = next.words.map((w) => w.word).join(' · '));
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
