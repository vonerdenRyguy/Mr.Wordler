import 'package:flutter/material.dart';

import 'tokens.dart';

enum ChunkyKind { primary, secondary, danger, mode }

enum ChunkySize { big, normal, small }

/// The app's one button: ink outline, rounded, with a solid bottom lip
/// that squashes when pressed so it looks pushed in.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ChunkyKind.primary,
    this.modeColor,
    this.icon,
    this.size = ChunkySize.normal,
    this.trailing,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ChunkyKind kind;
  // Fill for ChunkyKind.mode.
  final Color? modeColor;
  final IconData? icon;
  final ChunkySize size;
  // Optional extra widget after the label (e.g. a cost chip).
  final Widget? trailing;
  // Fill the available width.
  final bool expand;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final Color fill;
    final Color text;
    Color lipColor = WColors.ink;
    switch (widget.kind) {
      case ChunkyKind.primary:
        fill = WColors.grass;
        text = WColors.white;
        lipColor = WColors.grassLip;
      case ChunkyKind.secondary:
        fill = WColors.card;
        text = WColors.ink;
      case ChunkyKind.danger:
        fill = WColors.brick;
        text = WColors.white;
      case ChunkyKind.mode:
        fill = widget.modeColor ?? WColors.tile;
        text = WColors.ink;
    }
    final style = switch (widget.size) {
      ChunkySize.big => WText.buttonBig,
      ChunkySize.normal => WText.button,
      ChunkySize.small => WText.buttonSmall,
    };
    final minHeight = switch (widget.size) {
      ChunkySize.big => 56.0,
      ChunkySize.normal => WSize.tapTarget,
      ChunkySize.small => WSize.chipHeight,
    };
    final lip = !enabled ? 0.0 : (_pressed ? 1.0 : WSize.lip);
    final textColor = enabled ? text : WColors.muted;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: Padding(
          // Reserve the lip's space so pressing doesn't shift the layout.
          padding: const EdgeInsets.only(bottom: WSize.lip),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            transform: Matrix4.translationValues(0, enabled && _pressed ? 3 : 0, 0),
            constraints: BoxConstraints(minHeight: minHeight - WSize.lip),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: enabled ? fill : WColors.boardCell,
              border: Border.all(color: enabled ? WColors.ink : WColors.muted, width: WSize.outline),
              borderRadius: BorderRadius.circular(WSize.radiusButton),
              boxShadow: lip > 0 ? wLip(lip, color: lipColor) : null,
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: textColor, size: style.fontSize! + 4),
                  const SizedBox(width: WSize.gap2),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    style: style.copyWith(color: textColor),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: WSize.gap2),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 48x48 secondary-style icon button. The tooltip doubles as its
/// screen-reader label.
class ChunkyIconButton extends StatefulWidget {
  const ChunkyIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.fill = WColors.card,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color fill;

  @override
  State<ChunkyIconButton> createState() => _ChunkyIconButtonState();
}

class _ChunkyIconButtonState extends State<ChunkyIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: SizedBox(
            width: WSize.tapTarget,
            height: WSize.tapTarget,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
                width: WSize.tapTarget,
                height: WSize.tapTarget - WSize.lipSmall,
                decoration: BoxDecoration(
                  color: widget.fill,
                  border: Border.all(color: WColors.ink, width: WSize.outline),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: wLip(_pressed ? 1 : WSize.lipSmall),
                ),
                child: Icon(widget.icon, color: WColors.ink, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
