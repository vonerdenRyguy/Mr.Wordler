import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/letter_tile.dart';
import '../settings/settings_controller.dart';
import '../settings/word_level.dart';
import '../sound/sound_service.dart';
import 'family_online_screens.dart';
import 'family_screens.dart';
import 'word_level_screen.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../ui/wordler_scaffold.dart';

// Text size, Reduce motion and How to play. The Dark Mode switch stays
// hidden until there's a proper dark palette; ThemeNotifier and its saved
// value are kept as they are.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Offset _buttonPosition = const Offset(250, 520);
  final _random = Random();
  static const double _buttonSize = 60.0;

  void _moveButton(BoxConstraints constraints) {
    final maxX = (constraints.maxWidth - _buttonSize).clamp(0.0, double.infinity);
    final maxY = (constraints.maxHeight - _buttonSize).clamp(0.0, double.infinity);
    setState(() {
      _buttonPosition = Offset(
        _random.nextDouble() * maxX,
        _random.nextDouble() * maxY,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    return WordlerScaffold(
      title: 'Settings',
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(WSize.screenPadding),
                children: [
                  ChunkyCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Text size', style: WText.heading.copyWith(fontSize: 22)),
                        const SizedBox(height: WSize.gap2),
                        _ThreeWayToggle(
                          labels: SettingsData.textSizeLabels,
                          selected: settings.textSizeStep,
                          onSelected: controller.setTextSizeStep,
                        ),
                        const SizedBox(height: WSize.gap3),
                        const Text('Spell magic words to raise buildings.', style: WText.body),
                      ],
                    ),
                  ),
                  const SizedBox(height: WSize.gap3),
                  ChunkyCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Reduce motion', style: WText.heading.copyWith(fontSize: 22)),
                              Text('No bouncing tiles. Words still glow.',
                                  style: WText.body.copyWith(color: WColors.muted)),
                            ],
                          ),
                        ),
                        Switch(value: settings.reduceMotion, onChanged: controller.setReduceMotion),
                      ],
                    ),
                  ),
                  const SizedBox(height: WSize.gap3),
                  // Music and sounds (spec-12).
                  _SoundCard(
                    icon: Icons.music_note,
                    title: 'Music',
                    note: 'Soft tunes in your village, the Daily and Time Attack.',
                    on: settings.musicOn,
                    volume: settings.musicVolume,
                    onOn: controller.setMusicOn,
                    onVolume: controller.setMusicVolume,
                  ),
                  const SizedBox(height: WSize.gap3),
                  _SoundCard(
                    icon: Icons.notifications_active,
                    title: 'Sounds',
                    note: 'Tiles, words, coins and buildings. Everything still works with sound off.',
                    on: settings.soundsOn,
                    volume: settings.soundsVolume,
                    onOn: controller.setSoundsOn,
                    onVolume: controller.setSoundsVolume,
                    onVolumeEnd: (_) => ref.read(soundProvider).play(Sfx.coin),
                  ),
                  const SizedBox(height: WSize.gap3),
                  // Mr. W's tips on Home (spec-11).
                  ChunkyCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Show tips', style: WText.heading.copyWith(fontSize: 22)),
                              Text('Mr. W helps when you might be stuck.',
                                  style: WText.body.copyWith(color: WColors.muted)),
                            ],
                          ),
                        ),
                        Switch(value: settings.showTips, onChanged: controller.setShowTips),
                      ],
                    ),
                  ),
                  const SizedBox(height: WSize.gap3),
                  ChunkyCard(
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const WordLevelScreen())),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Word level', style: WText.heading.copyWith(fontSize: 22)),
                              Text('${settings.wordLevel.info.name}: ${settings.wordLevel.info.summary}',
                                  style: WText.body.copyWith(color: WColors.muted)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: WColors.ink),
                      ],
                    ),
                  ),
                  const SizedBox(height: WSize.gap3),
                  ChunkyCard(
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FamilyScreen())),
                    child: Row(
                      children: [
                        const Icon(Icons.group, color: WColors.ink, size: 28),
                        const SizedBox(width: WSize.gap3),
                        Expanded(child: Text('Players on this phone', style: WText.heading.copyWith(fontSize: 22))),
                        const Icon(Icons.chevron_right, color: WColors.ink),
                      ],
                    ),
                  ),
                  const SizedBox(height: WSize.gap3),
                  const FamilyOnlineRow(),
                  const SizedBox(height: WSize.gap3),
                  ChunkyCard(
                    onTap: () => showHowToPlay(context),
                    child: Row(
                      children: [
                        const Icon(Icons.help_outline, color: WColors.ink, size: 28),
                        const SizedBox(width: WSize.gap3),
                        Expanded(child: Text('How to play', style: WText.heading.copyWith(fontSize: 22))),
                        const Icon(Icons.chevron_right, color: WColors.ink),
                      ],
                    ),
                  ),
                  const SizedBox(height: WSize.gap5),
                  const Text('Mr. Wordler · version $kAppVersion', style: WText.label, textAlign: TextAlign.center),
                ],
              ),
              // Easter egg: this button runs away when you try to press it.
              Positioned(
                left: _buttonPosition.dx.clamp(0.0, max(0.0, constraints.maxWidth - _buttonSize)),
                top: _buttonPosition.dy.clamp(0.0, max(0.0, constraints.maxHeight - _buttonSize)),
                child: IconButton(
                  iconSize: _buttonSize - 10,
                  icon: const Icon(Icons.accessible_forward_sharp, color: WColors.coral),
                  onPressed: () => _moveButton(constraints),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Music or Sounds: a switch, and a volume slider while it's on.
class _SoundCard extends StatelessWidget {
  const _SoundCard({
    required this.icon,
    required this.title,
    required this.note,
    required this.on,
    required this.volume,
    required this.onOn,
    required this.onVolume,
    this.onVolumeEnd,
  });

  final IconData icon;
  final String title;
  final String note;
  final bool on;
  final double volume;
  final ValueChanged<bool> onOn;
  final ValueChanged<double> onVolume;
  final ValueChanged<double>? onVolumeEnd;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: WColors.ink, size: 28),
              const SizedBox(width: WSize.gap3),
              Expanded(child: Text(title, style: WText.heading.copyWith(fontSize: 22))),
              Switch(value: on, onChanged: onOn),
            ],
          ),
          if (on)
            Row(
              children: [
                const Icon(Icons.volume_down, color: WColors.muted),
                Expanded(
                  child: Slider(
                    value: volume,
                    onChanged: onVolume,
                    onChangeEnd: onVolumeEnd,
                    semanticFormatterCallback: (v) => '$title volume ${(v * 100).round()} percent',
                  ),
                ),
                const Icon(Icons.volume_up, color: WColors.muted),
              ],
            ),
          Text(note, style: WText.body.copyWith(color: WColors.muted)),
        ],
      ),
    );
  }
}

/// A soil track with three choices; the selected one is sun-filled.
class _ThreeWayToggle extends StatelessWidget {
  const _ThreeWayToggle({required this.labels, required this.selected, required this.onSelected});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: WSize.tapTarget - WSize.lip),
      margin: const EdgeInsets.only(bottom: WSize.lip),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: WColors.soil,
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: BorderRadius.circular(14),
        boxShadow: wLip(WSize.lip),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                label: 'Text size ${labels[i]}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? WColors.sun : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: i == selected ? Border.all(color: WColors.ink, width: WSize.outlineSmall) : null,
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: WText.buttonSmall.copyWith(color: i == selected ? WColors.ink : WColors.tile),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The 5-step "How to play" sheet.
Future<void> showHowToPlay(BuildContext context) {
  const steps = [
    ('CAT', 'Drag letters from your rack onto the board.'),
    ('WORD', 'Make real words across or down. Every word must touch another.'),
    ('WELL', 'Magic words like WELL and FARM become buildings in your village.'),
    ('TAP', 'Tap any word in Village view to learn what it means.'),
    ('CLUE', "The Daily puzzle has a theme and a secret word. Tap Clue if you'd like help."),
    ('EASY', 'Pick a word level in Settings to make the Daily puzzle smaller or bigger.'),
  ];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      decoration: const BoxDecoration(
        color: WColors.card,
        border: Border(top: BorderSide(color: WColors.ink, width: WSize.outline)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(WSize.radiusHero)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(WSize.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: const Text('How to play', style: WText.heading)),
              const SizedBox(height: WSize.gap3),
              for (int i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: WSize.gap3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}.', style: WText.button),
                      const SizedBox(width: WSize.gap2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Row(
                                children: [
                                  for (final l in steps[i].$1.split(''))
                                    Padding(
                                      padding: const EdgeInsets.only(right: 3),
                                      child: SizedBox(width: 28, height: 28, child: LetterTile(letter: l)),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(steps[i].$2, style: WText.body),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ChunkyButton(label: 'Got it', expand: true, onPressed: () => Navigator.of(sheetContext).pop()),
            ],
          ),
        ),
      ),
    ),
  );
}
