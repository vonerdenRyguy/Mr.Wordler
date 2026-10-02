import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chunky_button.dart';
import 'tokens.dart';

/// A paper-background screen with the app's top bar (64px: a back button
/// and a Lilita One title) instead of a Material AppBar. No color band, so
/// the paper runs all the way to the top.
class WordlerScaffold extends StatelessWidget {
  const WordlerScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.showBack = true,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        backgroundColor: WColors.paper,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WSize.screenPadding),
                  child: Row(
                    children: [
                      if (showBack) ...[
                        ChunkyIconButton(
                          icon: Icons.arrow_back,
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: WSize.gap3),
                      ],
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: WText.heading.copyWith(fontSize: 28),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
