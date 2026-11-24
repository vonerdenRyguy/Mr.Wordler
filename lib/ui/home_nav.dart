import 'package:flutter/material.dart';

import 'chunky_button.dart';
import 'tokens.dart';

// Home's way around (spec-11): page dots, a slim tab bar, Mr. W's tip and
// the first-time "swipe to look around" card.

class HomeTabInfo {
  const HomeTabInfo(this.label, this.icon, {this.badge = 0, this.alert = false});

  final String label;
  final IconData icon;

  /// A red number on the tab; 0 shows none.
  final int badge;

  /// A red "!": something new to do there today.
  final bool alert;
}

/// Small dots above the tab bar: which page you're on.
class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == index ? 22 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == index ? WColors.ink : WColors.boardBed,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

/// A slim bar of tabs, each a picture and a word. Swiping is the main way
/// around; the tabs are for anyone who'd rather tap.
class HomeTabBar extends StatelessWidget {
  const HomeTabBar({super.key, required this.tabs, required this.index, required this.onTap});

  final List<HomeTabInfo> tabs;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: WColors.soil,
        border: Border(top: BorderSide(color: WColors.ink, width: WSize.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (int i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _Tab(info: tabs[i], selected: i == index, onTap: () => onTap(i))),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.info, required this.selected, required this.onTap});

  final HomeTabInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? WColors.ink : WColors.tile;
    return Semantics(
      button: true,
      selected: selected,
      label: '${info.label}${info.badge > 0 ? ', ${info.badge} new' : ''}${info.alert ? ', something to play' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? WColors.sun : WColors.soilDeep,
                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                borderRadius: BorderRadius.circular(12),
                boxShadow: selected ? wLip(WSize.lipSmall) : null,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(info.icon, size: 20, color: fg),
                  const SizedBox(width: 6),
                  Text(info.label, style: WText.buttonSmall.copyWith(color: fg)),
                ]),
              ),
            ),
            if (info.badge > 0 || info.alert)
              Positioned(
                top: -8,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: WColors.brick,
                    border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    info.badge == 0
                        ? '!'
                        : info.badge > 9
                            ? '9+'
                            : '${info.badge}',
                    textScaler: TextScaler.noScaling,
                    style: WText.buttonSmall.copyWith(fontSize: 13, color: WColors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mr. W: a tilted W tile, the face of the app's tips.
class MrW extends StatelessWidget {
  const MrW({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: -0.1,
        child: Container(
          width: size,
          height: size * 1.1,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: WColors.sun,
            border: Border.all(color: WColors.ink, width: WSize.outline),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text('W',
              textScaler: TextScaler.noScaling,
              style: WText.button.copyWith(fontSize: size * 0.6, color: WColors.ink)),
        ),
      ),
    );
  }
}

/// One short tip from Mr. W, with an X to hide it.
class TipBar extends StatelessWidget {
  const TipBar({super.key, required this.text, required this.onHide});

  final String text;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Tip: $text',
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: WColors.white,
          border: Border.all(color: WColors.ink, width: WSize.outline),
          borderRadius: BorderRadius.circular(18),
          boxShadow: wLip(WSize.lipSmall),
        ),
        child: Row(children: [
          const MrW(),
          const SizedBox(width: 10),
          Expanded(child: ExcludeSemantics(child: Text(text, style: WText.body.copyWith(fontSize: 15)))),
          IconButton(
            tooltip: 'Hide tip',
            onPressed: onHide,
            icon: const Icon(Icons.close, color: WColors.muted),
          ),
        ]),
      ),
    );
  }
}

/// The first-time card: swipe to look around, and what each page holds.
class HomeIntroCard extends StatelessWidget {
  const HomeIntroCard({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String name, String what) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: WColors.sun,
                shape: BoxShape.circle,
                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
              ),
              child: Icon(icon, size: 18, color: WColors.ink),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(style: WText.body, children: [
                TextSpan(text: name, style: WText.bodyBold),
                TextSpan(text: ': $what'),
              ])),
            ),
          ]),
        );
    return Material(
      color: WColors.ink.withOpacity(0.55),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: WColors.card,
                border: Border.all(color: WColors.ink, width: WSize.outline),
                borderRadius: BorderRadius.circular(WSize.radiusHero),
                boxShadow: wLip(WSize.lipHero),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.swipe, size: 48, color: WColors.ink),
                  SizedBox(width: 10),
                  MrW(size: 44),
                ]),
                const SizedBox(height: 10),
                Semantics(
                  header: true,
                  child: Text('Swipe to look around', textAlign: TextAlign.center, style: WText.heading.copyWith(fontSize: 28)),
                ),
                const SizedBox(height: 10),
                line(Icons.person, 'Me', 'your level, words and stats'),
                line(Icons.home, 'Play', 'your village and games (you are here)'),
                line(Icons.groups, 'Family', 'play together'),
                const SizedBox(height: 14),
                ChunkyButton(label: 'Got it', expand: true, size: ChunkySize.big, onPressed: onDone),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
