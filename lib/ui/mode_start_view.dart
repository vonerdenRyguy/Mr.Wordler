import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chunky_button.dart';
import 'chunky_card.dart';
import 'tokens.dart';

/// One "How it works" line: a short symbol in a small tile, then a line.
class ModeStartRow {
  const ModeStartRow(this.symbol, this.text);

  final String symbol;
  final String text;
}

/// One small stats card: a label above a number.
class ModeStartStat {
  const ModeStartStat(this.label, this.value);

  final String label;
  final String value;
}

/// The short page before a round starts: a big mode-colored hero, three
/// "How it works" lines, real stats (if any), and a big Start button.
class ModeStartView extends StatelessWidget {
  const ModeStartView({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.description,
    required this.rows,
    this.stats = const [],
    this.startLabel = 'Start',
    required this.onStart,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String description;
  final List<ModeStartRow> rows;
  final List<ModeStartStat> stats;
  final String startLabel;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        backgroundColor: WColors.paper,
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(WSize.screenPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ChunkyIconButton(
                            icon: Icons.arrow_back,
                            tooltip: 'Home',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: WSize.gap2),
                          const Text('Home', style: WText.label),
                        ],
                      ),
                      const SizedBox(height: WSize.gap4),
                      Center(
                        child: Container(
                          width: 112,
                          height: 112,
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: color,
                            border: Border.all(color: WColors.ink, width: 4),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: wLip(6),
                          ),
                          child: Icon(icon, size: 62, color: WColors.ink),
                        ),
                      ),
                      const SizedBox(height: WSize.gap3),
                      Semantics(
                        header: true,
                        child: Text(title, style: WText.title, textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: WSize.gap1),
                      Text(description, style: WText.body.copyWith(fontSize: 19), textAlign: TextAlign.center),
                      const SizedBox(height: WSize.gap5),
                      ChunkyCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('How it works', style: WText.heading.copyWith(fontSize: 21)),
                            const SizedBox(height: WSize.gap2),
                            for (final row in rows)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: color,
                                        border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Text(row.symbol, style: WText.button.copyWith(fontSize: 17, color: WColors.ink)),
                                    ),
                                    const SizedBox(width: WSize.gap3),
                                    Expanded(child: Text(row.text, style: WText.bodyBold)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (stats.isNotEmpty) ...[
                        const SizedBox(height: WSize.gap3),
                        Row(
                          children: [
                            for (int i = 0; i < stats.length; i++) ...[
                              if (i > 0) const SizedBox(width: WSize.gap3),
                              Expanded(
                                child: ChunkyCard(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(stats[i].label, style: WText.label),
                                      Text(stats[i].value, style: WText.number.copyWith(fontSize: 26)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: WSize.gap4),
                      ChunkyButton(label: startLabel, size: ChunkySize.big, expand: true, onPressed: onStart),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "MM:SS" for a number of seconds.
String formatSeconds(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
