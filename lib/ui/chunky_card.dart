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
    final card = Container(
      margin: EdgeInsets.only(bottom: hero ? WSize.lipHero : WSize.lip),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: radius,
        boxShadow: wLip(hero ? WSize.lipHero : WSize.lip),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular((hero ? WSize.radiusHero : WSize.radiusCard) - WSize.outline),
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
