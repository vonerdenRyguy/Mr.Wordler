import 'dart:math';

import 'package:flutter/material.dart';

/// What a tile should animate. Records give value equality for select().
typedef TileFx = ({int seq, bool settle, int popOrder}); // popOrder -1 = not in a new word

const _face = Color(0xFFF3E3C3);
const _ink = Color(0xFF3B2A1E);
const _glowFace = Color(0xFFFFF3C4);
const _glowRing = Color(0xFFF6C443);
const _pinFace = Color(0xFFFBE7C9);
const _pinAccent = Color(0xFFB7791F);
const _pinBadgeBorder = Color(0xFFFFFDF8);

const _settleMs = 180;
const _popMs = 280;
const _popStaggerMs = 45;
const _glowMs = 1000;

/// One letter drawn as a chunky wooden game piece: cream face, dark
/// outline and a solid bottom lip. No Riverpod and no drag logic, so it
/// can be reused anywhere a letter is shown. [fx] drives the word-landing
/// animation (see word_landing.dart); null means no animation.
class LetterTile extends StatefulWidget {
  const LetterTile({
    super.key,
    required this.letter,
    this.isBoard = false,
    this.isPinned = false,
    this.fx,
  });

  final String letter;
  final bool isBoard;
  final bool isPinned;
  final TileFx? fx;

  /// The plain face with no letter, used as the "ghost" left behind while
  /// a tile is being dragged.
  static Widget ghost() => LayoutBuilder(builder: (context, constraints) {
        final side = min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              color: _face.withOpacity(0.35),
              borderRadius: BorderRadius.circular(side * 0.18),
            ),
          ),
        );
      });

  @override
  State<LetterTile> createState() => _LetterTileState();
}

class _LetterTileState extends State<LetterTile> with SingleTickerProviderStateMixin {
  // Starts at the end (value 1.0 = resting look), so a tile that never
  // lands shows no effect.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: _glowMs), value: 1.0);
    // A tile that has just landed is usually built fresh (its cell had no
    // tile before), so the landing is already in fx here.
    if (widget.fx != null) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(LetterTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fx = widget.fx;
    final old = oldWidget.fx;
    if (fx == null) return;
    final newLanding = old == null || old.seq != fx.seq;
    final wordArrived = !newLanding && old.popOrder < 0 && fx.popOrder >= 0;
    if (newLanding || wordArrived) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 0..1 progress of [startMs, startMs + lengthMs] within the controller.
  double _interval(double t, int startMs, int lengthMs, Curve curve) {
    final start = startMs / _glowMs;
    final end = min(1.0, (startMs + lengthMs) / _glowMs);
    if (t <= start) return 0;
    if (t >= end) return 1;
    return curve.transform((t - start) / (end - start));
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return LayoutBuilder(builder: (context, constraints) {
      final side = min(constraints.maxWidth, constraints.maxHeight);
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final fx = widget.fx;
          final running = _controller.isAnimating;
          final inWord = fx != null && fx.popOrder >= 0;

          var scale = 1.0;
          if (!reduceMotion && fx != null && running) {
            if (fx.settle) {
              scale *= 0.88 + 0.12 * _interval(t, 0, _settleMs, Curves.easeOutBack);
            }
            if (inWord) {
              final p = _interval(t, fx.popOrder * _popStaggerMs, _popMs, Curves.easeInOut);
              scale *= 1 + 0.14 * (p < 0.5 ? p * 2 : (1 - p) * 2);
            }
          }
          // Glow fades back to normal over the whole 1000ms; with reduce
          // motion it stays on, unfaded, for that time.
          final glow = inWord && running ? (reduceMotion ? 1.0 : 1.0 - t) : 0.0;

          final tile = _buildTile(side, glow);
          return scale == 1.0 ? tile : Transform.scale(scale: scale, child: tile);
        },
      );
    });
  }

  Widget _buildTile(double side, double glow) {
    final pinned = widget.isPinned;
    final lip = (side * 0.07).clamp(2.0, 4.0);
    final outlineWidth = pinned ? 2.5 : (widget.isBoard ? (side < 30 ? 1.0 : 1.5) : 2.0);
    final outlineColor = pinned ? _pinAccent : _ink;
    final baseFace = pinned ? _pinFace : _face;
    final face = Color.lerp(baseFace, _glowFace, glow)!;

    final tile = SizedBox(
      width: side,
      height: side,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: side,
          height: side - lip,
          decoration: BoxDecoration(
            color: face,
            border: Border.all(color: outlineColor, width: outlineWidth),
            borderRadius: BorderRadius.circular(side * 0.18),
            boxShadow: [
              if (glow > 0) BoxShadow(color: _glowRing.withOpacity(glow), spreadRadius: 3, blurRadius: 0),
              BoxShadow(color: pinned ? _pinAccent : _ink, offset: Offset(0, lip), blurRadius: 0),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.letter,
            style: TextStyle(
              fontFamily: 'LilitaOne',
              color: _ink,
              fontSize: (side * 0.6).clamp(12.0, 34.0),
              height: 1.0,
            ),
          ),
        ),
      ),
    );

    final labeled = Semantics(label: 'Letter ${widget.letter}', excludeSemantics: true, child: tile);
    if (!pinned) return labeled;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        labeled,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: _pinAccent,
              shape: BoxShape.circle,
              border: Border.all(color: _pinBadgeBorder, width: 2),
            ),
            child: const Icon(Icons.push_pin, size: 11, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
