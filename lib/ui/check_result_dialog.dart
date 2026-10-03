import 'package:flutter/material.dart';

import '../components/valid_word_check.dart' show WordCheckResult;
import 'tokens.dart';
import 'wordler_dialog.dart';

/// The result of a Check that didn't win: words not all connected, or the
/// words found (valid in green, or invalid in red). Shared by the 10x10
/// modes.
void showCheckResultDialog(BuildContext context, WordCheckResult result) {
  if (!result.areConnected && result.areValid) {
    // Words are valid individually but not all touching.
    showWordlerDialog<void>(
      context,
      title: 'All valid words must be connected',
      actions: [WordlerDialogAction('OK', () {})],
    );
    return;
  }
  showWordlerDialog<void>(
    context,
    title: result.areValid ? 'Valid Words!' : 'Invalid Words:',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final word in result.words)
          Text(word, style: WText.bodyBold.copyWith(color: result.areValid ? WColors.grass : WColors.brick)),
      ],
    ),
    actions: [WordlerDialogAction('OK', () {})],
  );
}
