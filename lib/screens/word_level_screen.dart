import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/letter_tile.dart';
import '../settings/settings_controller.dart';
import '../settings/word_level.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../ui/wordler_scaffold.dart';

// Pick your word level (spec-06): the size of your Daily puzzle. Opened
// from Settings, and once before a new player's first Daily. Pops with
// true when a level was saved.
class WordLevelScreen extends ConsumerStatefulWidget {
  const WordLevelScreen({super.key});

  @override
  ConsumerState<WordLevelScreen> createState() => _WordLevelScreenState();
}

class _WordLevelScreenState extends ConsumerState<WordLevelScreen> {
  late WordLevel _picked = ref.read(settingsProvider).wordLevel;

  Future<void> _use() async {
    await ref.read(settingsProvider.notifier).setWordLevel(_picked);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return WordlerScaffold(
      title: 'Your word level',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(WSize.screenPadding),
              children: [
                const Text(
                  'This sets the size of your Daily puzzle. It is not a test, and you can change it any time.',
                  style: WText.body,
                ),
                const SizedBox(height: WSize.gap3),
                for (final level in WordLevel.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: WSize.gap3),
                    child: _LevelCard(
                      level: level,
                      selected: level == _picked,
                      onTap: () => setState(() => _picked = level),
                    ),
                  ),
                const Text('Every level earns the same coins.', style: WText.label, textAlign: TextAlign.center),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 0, WSize.screenPadding, WSize.screenPadding),
              child: ChunkyButton(
                label: 'Use ${_picked.info.name}',
                size: ChunkySize.big,
                expand: true,
                onPressed: _use,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level, required this.selected, required this.onTap});

  final WordLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = level.info;
    return Semantics(
      button: true,
      selected: selected,
      label: '${info.name}. ${info.summary} ${info.detail} ${info.goodFor}.',
      excludeSemantics: true,
      child: ChunkyCard(
        color: selected ? WColors.sunTint : WColors.card,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 48, height: 48, child: LetterTile(letter: info.name[0], faceColor: info.color)),
            const SizedBox(width: WSize.gap3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(info.name, style: WText.heading.copyWith(fontSize: 22))),
                      if (selected) ...[
                        const SizedBox(width: WSize.gap2),
                        const Icon(Icons.check_circle, color: WColors.grass, size: 22),
                      ],
                    ],
                  ),
                  Text(info.summary, style: WText.bodyBold.copyWith(fontSize: 15)),
                  Text(info.detail, style: WText.body.copyWith(fontSize: 15)),
                  Text(info.goodFor, style: WText.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
