import 'package:flutter/material.dart';

import 'tokens.dart';

/// A card with an ink outline and a solid bottom lip. `hero` is the
/// bigger, rounder version for a screen's main card.
class ChunkyCard extends StatelessWidget {
  const ChunkyCard({
    super.key,
    required this.child,
    this.color = WColors.card,
    this.hero = false,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.stripe,
  });

  final Widget child;
  final Color color;
  final bool hero;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  // Optional 6px accent stripe down the left edge, inside the card.
  final Color? stripe;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(hero ? WSize.radiusHero : WSize.radiusCard);
    Widget content = Padding(padding: padding, child: child);
    if (stripe != null) {
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: stripe),
            Expanded(child: content),
          ],
        ),
      );
    }
    // Only things you can tap get the ink outline and lip (spec-12); the
    // rest sit on a soft shadow, so tappable things stand out.
    final tappable = onTap != null;
    final card = Container(
      margin: EdgeInsets.only(bottom: hero ? WSize.lipHero : WSize.lip),
      decoration: BoxDecoration(
        color: color,
        border: tappable ? Border.all(color: WColors.ink, width: WSize.outline) : null,
        borderRadius: radius,
        boxShadow: tappable
            ? wLip(hero ? WSize.lipHero : WSize.lip)
            : const [BoxShadow(color: Color(0x2E3B2A1E), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular((hero ? WSize.radiusHero : WSize.radiusCard) - (tappable ? WSize.outline : 0)),
        child: content,
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card),
    );
  }
}
