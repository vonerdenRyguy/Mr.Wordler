import 'package:flutter/material.dart';

import 'tokens.dart';

/// A 44px pill: a round icon badge, a value in Lilita One, and an optional
/// muted label after it (e.g. "292 pts"). Tappable when [onTap] is set.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.icon,
    required this.value,
    this.label,
    this.badgeColor = WColors.sun,
    this.color = WColors.card,
    this.onTap,
    this.tooltip,
    this.enabled = true,
  });

  final IconData icon;
  final String value;
  final String? label;
  final Color badgeColor;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final textColor = enabled ? WColors.ink : WColors.muted;
    Widget chip = Container(
      height: WSize.chipHeight - WSize.lipSmall,
      margin: const EdgeInsets.only(bottom: WSize.lipSmall),
      padding: const EdgeInsets.only(left: 6, right: 14),
      decoration: BoxDecoration(
        color: enabled ? color : WColors.boardCell,
        border: Border.all(color: enabled ? WColors.ink : WColors.muted, width: WSize.outlineSmall),
        borderRadius: BorderRadius.circular(WSize.radiusChip),
        boxShadow: enabled ? wLip(WSize.lipSmall) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: enabled ? badgeColor : WColors.boardCell,
              shape: BoxShape.circle,
              border: Border.all(color: textColor, width: WSize.outlineSmall),
            ),
            child: Icon(icon, size: 16, color: textColor),
          ),
          const SizedBox(width: WSize.gap2),
          Text(value, style: WText.button.copyWith(color: textColor)),
          if (label != null) ...[
            const SizedBox(width: WSize.gap1),
            Text(label!, style: WText.label),
          ],
        ],
      ),
    );
    if (tooltip != null) chip = Tooltip(message: tooltip!, child: chip);
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: enabled ? onTap : null, child: chip),
    );
  }
}
