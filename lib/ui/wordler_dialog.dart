import 'package:flutter/material.dart';

import 'chunky_button.dart';
import 'tokens.dart';

/// One action at the bottom of a WordlerDialog.
class WordlerDialogAction {
  const WordlerDialogAction(this.label, this.onPressed, {this.kind = ChunkyKind.primary});

  final String label;
  final VoidCallback onPressed;
  final ChunkyKind kind;
}

/// The app's one dialog: card fill, ink outline, a 5px lip, a heading
/// title, and full-width chunky buttons stacked with the main one first.
class WordlerDialog extends StatelessWidget {
  const WordlerDialog({
    super.key,
    required this.title,
    this.body,
    this.bodyText,
    required this.actions,
    this.icon,
  });

  final String title;
  // Either a custom body widget or plain body text.
  final Widget? body;
  final String? bodyText;
  final List<WordlerDialogAction> actions;
  // Optional icon before the title.
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        margin: const EdgeInsets.only(bottom: WSize.lipHero),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: WColors.card,
          border: Border.all(color: WColors.ink, width: WSize.outline),
          borderRadius: BorderRadius.circular(WSize.radiusHero),
          boxShadow: wLip(WSize.lipHero),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: WSize.gap2)],
                  Expanded(child: Semantics(header: true, child: Text(title, style: WText.heading))),
                ],
              ),
              const SizedBox(height: WSize.gap3),
              if (body != null) DefaultTextStyle(style: WText.body, child: body!),
              if (bodyText != null) Text(bodyText!, style: WText.body),
              const SizedBox(height: WSize.gap4),
              for (final action in actions) ...[
                ChunkyButton(
                  label: action.label,
                  onPressed: action.onPressed,
                  kind: action.kind,
                  expand: true,
                ),
                const SizedBox(height: WSize.gap2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a WordlerDialog. Each action closes the dialog, then runs.
Future<T?> showWordlerDialog<T>(
  BuildContext context, {
  required String title,
  String? bodyText,
  Widget? body,
  Widget? icon,
  required List<WordlerDialogAction> actions,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => WordlerDialog(
      title: title,
      bodyText: bodyText,
      body: body,
      icon: icon,
      actions: [
        for (final action in actions)
          WordlerDialogAction(
            action.label,
            () {
              Navigator.of(dialogContext).pop();
              action.onPressed();
            },
            kind: action.kind,
          ),
      ],
    ),
  );
}
