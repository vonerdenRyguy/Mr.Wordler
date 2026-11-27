import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../portfolio/portfolio_controller.dart';
import '../sound/sound_service.dart';
import 'chunky_button.dart';
import 'tokens.dart';

// Reward moments (spec-12): the page dims, a card says what you did and
// what you got, and the button flies the coins up into a coin counter that
// counts up. The coins are already paid when the moment opens, so closing
// it any way at all never loses them. With Reduce motion nothing flies or
// drops: the number just changes, and the sounds still play.

/// Shows a reward moment. [coins] must already have been added to the
/// player's coins. [picture] (a building, say) drops in above the title,
/// under an optional [ribbon] ("New building!").
Future<void> showRewardMoment(
  BuildContext context, {
  required String title,
  String? word,
  String? message,
  int coins = 0,
  Widget? picture,
  String? ribbon,
  String buttonLabel = 'Collect',
  Sfx sound = Sfx.reward,
  bool lookThrough = false,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: title,
    barrierColor: Colors.black.withOpacity(lookThrough ? 0.12 : 0.55),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, _, __) => RewardMoment(
      title: title,
      word: word,
      message: message,
      coins: coins,
      picture: picture,
      ribbon: ribbon,
      buttonLabel: buttonLabel,
      sound: sound,
      lookThrough: lookThrough,
    ),
  );
}

class RewardMoment extends ConsumerStatefulWidget {
  const RewardMoment({
    super.key,
    required this.title,
    this.word,
    this.message,
    this.coins = 0,
    this.picture,
    this.ribbon,
    this.buttonLabel = 'Collect',
    this.sound = Sfx.reward,
    this.lookThrough = false,
  });

  /// The card sits at the bottom, so what's behind it can be seen.
  final bool lookThrough;

  final String title;
  final String? word;
  final String? message;
  final int coins;
  final Widget? picture;
  final String? ribbon;
  final String buttonLabel;
  final Sfx sound;

  static const flyCoins = 8;

  @override
  ConsumerState<RewardMoment> createState() => _RewardMomentState();
}

class _RewardMomentState extends ConsumerState<RewardMoment> with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _fly;
  final _stackKey = GlobalKey();
  final _buttonKey = GlobalKey();
  final _counterKey = GlobalKey();
  late final int _endCoins;
  Offset? _from;
  Offset? _to;
  bool _collecting = false;
  bool _jumped = false; // Reduce motion: the counter has jumped to the end
  int _clinks = 0;

  @override
  void initState() {
    super.initState();
    _endCoins = ref.read(portfolioProvider).currency;
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();
    _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..addListener(_clinkAsCoinsLand)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _closeSoon(const Duration(milliseconds: 350));
      });
    HapticFeedback.mediumImpact();
    ref.read(soundProvider).play(widget.sound);
  }

  @override
  void dispose() {
    _intro.dispose();
    _fly.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  int get _startCoins => max(0, _endCoins - widget.coins);

  /// How far coin [i] is along its flight, 0..1.
  double _coinT(int i) {
    const spread = 0.45; // the last coin leaves this far into the flight
    final start = spread * i / (RewardMoment.flyCoins - 1);
    return ((_fly.value - start) / (1 - spread)).clamp(0.0, 1.0);
  }

  int get _landed => [for (int i = 0; i < RewardMoment.flyCoins; i++) _coinT(i)].where((t) => t >= 1).length;

  void _clinkAsCoinsLand() {
    final landed = _landed;
    // A clink for the first coin, one midway and one for the last.
    final want = landed >= RewardMoment.flyCoins ? 3 : (landed >= RewardMoment.flyCoins ~/ 2 ? 2 : (landed > 0 ? 1 : 0));
    while (_clinks < want) {
      _clinks++;
      ref.read(soundProvider).play(Sfx.coin);
    }
  }

  int get _shownCoins {
    if (!_collecting) return _startCoins;
    if (_jumped) return _endCoins;
    return _startCoins + (widget.coins * _landed / RewardMoment.flyCoins).round();
  }

  Offset? _centerOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.hasSize) return null;
    return stack.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  }

  void _collect() {
    if (_collecting) return;
    if (widget.coins <= 0) {
      Navigator.of(context).pop();
      return;
    }
    _from = _centerOf(_buttonKey);
    _to = _centerOf(_counterKey);
    setState(() => _collecting = true);
    if (_reduceMotion || _from == null || _to == null) {
      ref.read(soundProvider).play(Sfx.coin);
      setState(() => _jumped = true);
      _closeSoon(const Duration(milliseconds: 700));
    } else {
      _fly.forward(from: 0);
    }
  }

  /// Holds the full counter for a moment, then closes. Runs on an
  /// animation (not a timer) so it keeps to the frame clock.
  void _closeSoon(Duration delay) {
    final hold = AnimationController(vsync: this, duration: delay);
    hold.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      hold.dispose();
      if (mounted) Navigator.of(context).pop();
    });
    hold.forward();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = _reduceMotion;
    return PopScope(
      // Back always works; the coins are already paid.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          key: _stackKey,
          children: [
            // The coin counter the coins fly into.
            if (widget.coins > 0)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(WSize.screenPadding),
                    child: AnimatedBuilder(
                      animation: _fly,
                      builder: (context, _) => _CoinCounter(key: _counterKey, coins: _shownCoins, glow: _collecting),
                    ),
                  ),
                ),
              ),
            Align(
              alignment: widget.lookThrough ? Alignment.bottomCenter : Alignment.center,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(WSize.gap5),
                child: AnimatedBuilder(
                  animation: _intro,
                  builder: (context, child) {
                    final t = reduce ? 1.0 : Curves.easeOutBack.transform(min(1.0, _intro.value / 0.6));
                    return Opacity(
                      opacity: reduce ? 1.0 : (_intro.value / 0.3).clamp(0.0, 1.0),
                      child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
                    );
                  },
                  child: _card(reduce),
                ),
              ),
            ),
            if (_collecting && !_jumped && _from != null && _to != null)
              AnimatedBuilder(
                animation: _fly,
                builder: (context, _) => Stack(children: [
                  for (int i = 0; i < RewardMoment.flyCoins; i++) _flyingCoin(i),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _flyingCoin(int i) {
    final t = _coinT(i);
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final from = _from!, to = _to!;
    // A curved path: each coin bows out a little to its own side.
    final side = (i.isEven ? 1 : -1) * (30.0 + 12 * (i % 3));
    final control = Offset((from.dx + to.dx) / 2 + side, min(from.dy, to.dy) - 40);
    final e = Curves.easeIn.transform(t);
    final p = from * ((1 - e) * (1 - e)) + control * (2 * (1 - e) * e) + to * (e * e);
    final size = 30.0 - 10 * e;
    return Positioned(
      left: p.dx - size / 2,
      top: p.dy - size / 2,
      child: IgnorePointer(child: _Coin(size: size)),
    );
  }

  Widget _card(bool reduce) {
    final picture = widget.picture;
    final ribbon = widget.ribbon;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            margin: EdgeInsets.only(top: ribbon == null ? 0 : 20),
            padding: EdgeInsets.fromLTRB(WSize.gap5, ribbon == null ? WSize.gap5 : 36, WSize.gap5, WSize.gap5),
            decoration: BoxDecoration(
              color: WColors.card,
              borderRadius: BorderRadius.circular(WSize.radiusHero),
              border: Border.all(color: WColors.ink, width: WSize.outline),
              boxShadow: wLip(WSize.lipHero),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (picture != null) ...[
                  SizedBox(height: 170, child: _DropIn(controller: _intro, reduce: reduce, child: picture)),
                  const SizedBox(height: WSize.gap3),
                ],
                Text(widget.title, textAlign: TextAlign.center, style: WText.heading),
                if (widget.word != null) ...[
                  const SizedBox(height: WSize.gap2),
                  Text(widget.word!.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: WText.title.copyWith(fontSize: 36, letterSpacing: 2, color: WColors.grass)),
                ],
                if (widget.message != null) ...[
                  const SizedBox(height: WSize.gap2),
                  Text(widget.message!, textAlign: TextAlign.center, style: WText.body),
                ],
                if (widget.coins > 0) ...[
                  const SizedBox(height: WSize.gap4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Coin(size: 34),
                      const SizedBox(width: WSize.gap2),
                      Text('+${widget.coins}', style: WText.number.copyWith(fontSize: 34)),
                    ],
                  ),
                ],
                const SizedBox(height: WSize.gap4),
                AnimatedOpacity(
                  opacity: _collecting ? 0.4 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: ChunkyButton(
                    key: _buttonKey,
                    label: widget.buttonLabel,
                    size: ChunkySize.big,
                    expand: true,
                    onPressed: _collecting ? null : _collect,
                  ),
                ),
              ],
            ),
          ),
          if (ribbon != null) _Ribbon(text: ribbon),
        ],
      ),
    );
  }
}

/// The picture falls into place with a bounce and a puff of dust.
class _DropIn extends StatelessWidget {
  const _DropIn({required this.controller, required this.reduce, required this.child});

  final AnimationController controller;
  final bool reduce;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduce) return child;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final v = controller.value;
        final fall = Curves.bounceOut.transform(v);
        // Dust starts when the picture first touches down (~35% in).
        final dust = ((v - 0.35) / 0.65).clamp(0.0, 1.0);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            if (dust > 0 && dust < 1)
              Positioned(
                bottom: 0,
                child: CustomPaint(size: const Size(220, 40), painter: _DustPainter(dust)),
              ),
            Transform.translate(offset: Offset(0, -120 * (1 - fall)), child: child),
          ],
        );
      },
      child: child,
    );
  }
}

class _DustPainter extends CustomPainter {
  _DustPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFD8C7A6).withOpacity(0.8 * (1 - t));
    final base = Offset(size.width / 2, size.height - 6);
    for (int i = 0; i < 6; i++) {
      final dir = i < 3 ? -1.0 : 1.0;
      final k = (i % 3) + 1;
      final c = base + Offset(dir * (18 + 28 * k * t), -6 * k * t);
      canvas.drawCircle(c, 6 + 6 * t + 2 * k, paint);
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) => old.t != t;
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      decoration: BoxDecoration(
        color: WColors.sun,
        borderRadius: BorderRadius.circular(WSize.radiusButton),
        border: Border.all(color: WColors.ink, width: WSize.outline),
        boxShadow: wLip(WSize.lipSmall),
      ),
      child: Text(text, style: WText.buttonBig.copyWith(color: WColors.ink)),
    );
  }
}

class _CoinCounter extends StatelessWidget {
  const _CoinCounter({super.key, required this.coins, required this.glow});
  final int coins;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$coins coins',
      liveRegion: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
        decoration: BoxDecoration(
          color: WColors.card,
          borderRadius: BorderRadius.circular(WSize.radiusChip),
          border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
          boxShadow: glow ? [BoxShadow(color: WColors.sun.withOpacity(0.9), blurRadius: 16, spreadRadius: 2)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Coin(size: 26),
            const SizedBox(width: WSize.gap2),
            ExcludeSemantics(child: Text('$coins', style: WText.number.copyWith(fontSize: 22))),
          ],
        ),
      ),
    );
  }
}

/// A gold coin, drawn (no image needed).
class _Coin extends StatelessWidget {
  const _Coin({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: WColors.sun,
        border: Border.all(color: WColors.ink, width: max(1.5, size / 14)),
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.55,
        height: size * 0.55,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFD99A1E), width: max(1.0, size / 16)),
        ),
      ),
    );
  }
}
