import 'package:flutter/material.dart';

import '../ui/tokens.dart';

// How a villager looks (spec-16). Placeholder art, drawn in code: a round
// head with their first letter on a coloured body. The colour comes from
// their id, so it never changes. Swapped for real art in the art pass.

const _bodyColors = <Color>[
  Color(0xFF7FB8E0),
  Color(0xFFE3A6C8),
  Color(0xFF9BCB6E),
  Color(0xFFF6C443),
  Color(0xFFE57373),
  Color(0xFFB39DDB),
  Color(0xFFFFB74D),
  Color(0xFF4DB6AC),
];

const villagerSkin = Color(0xFFF8D9B8);

Color villagerColor(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _bodyColors[h % _bodyColors.length];
}

String villagerInitial(String name) => name.isEmpty ? '?' : name.characters.first.toUpperCase();

/// A villager's face and body, [size] tall-ish (the head is size * 0.62).
class VillagerFace extends StatelessWidget {
  const VillagerFace({super.key, required this.id, required this.name, this.size = 56, this.happy = false});

  final String id;
  final String name;
  final double size;

  /// A best friend wears a pink body.
  final bool happy;

  @override
  Widget build(BuildContext context) {
    final head = size * 0.62;
    return ExcludeSemantics(
      child: SizedBox(
        width: size * 0.9,
        height: size,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              width: size * 0.9,
              height: size * 0.48,
              decoration: BoxDecoration(
                color: happy ? const Color(0xFFE3A6C8) : villagerColor(id),
                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                borderRadius: BorderRadius.vertical(top: Radius.circular(size * 0.3), bottom: const Radius.circular(6)),
              ),
            ),
            Positioned(
              top: 0,
              child: Container(
                width: head,
                height: head,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: villagerSkin,
                  shape: BoxShape.circle,
                  border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                ),
                child: Text(
                  villagerInitial(name),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontFamily: WFonts.display, fontSize: head * 0.55, color: WColors.ink, height: 1.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 5 hearts, [filled] of them pink.
class Hearts extends StatelessWidget {
  const Hearts({super.key, required this.filled, this.size = 20});

  final int filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$filled of 5 hearts',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(
                i < filled ? Icons.favorite : Icons.favorite_border,
                size: size,
                color: i < filled ? const Color(0xFFE2557A) : WColors.muted,
              ),
            ),
        ],
      ),
    );
  }
}
