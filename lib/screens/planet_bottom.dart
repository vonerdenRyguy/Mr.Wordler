import 'package:flutter/material.dart';

import '../letterra/something_to_find.dart';
import '../ui/chunky_button.dart';
import '../ui/tokens.dart';

/// Find my village, with the card for what glows (when something is left).
class PlanetBottom extends StatelessWidget {
  const PlanetBottom({super.key, required this.find, required this.onFindMe, required this.onTurn, required this.onShow});

  final SomethingToFind? find;
  final VoidCallback onFindMe;
  final VoidCallback onTurn;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final f = find;
    if (f == null) {
      return ChunkyButton(
        label: 'Find my village',
        icon: Icons.my_location,
        kind: ChunkyKind.mode,
        modeColor: WColors.sun,
        size: ChunkySize.big,
        expand: true,
        onPressed: onFindMe,
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: WColors.card,
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: BorderRadius.circular(WSize.radiusHero),
        boxShadow: wLip(WSize.lip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTurn,
            child: Column(children: [
              Text(
                'Something glows in ${f.region}',
                textAlign: TextAlign.center,
                style: WText.heading.copyWith(fontSize: 20, color: WColors.ink),
              ),
              const SizedBox(height: 2),
              Text(
                '${f.squares} square${f.squares == 1 ? '' : 's'} away. Words there need ${f.minLength} letters or more.',
                textAlign: TextAlign.center,
                style: WText.body.copyWith(fontSize: 16, color: WColors.ink),
              ),
            ]),
          ),
          const SizedBox(height: WSize.gap2),
          Row(children: [
            Expanded(
              child: ChunkyButton(label: 'My village', kind: ChunkyKind.secondary, expand: true, onPressed: onFindMe),
            ),
            const SizedBox(width: WSize.gap2),
            Expanded(
              child: ChunkyButton(
                label: 'Show me',
                kind: ChunkyKind.mode,
                modeColor: WColors.sun,
                expand: true,
                onPressed: onShow,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
