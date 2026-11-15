import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily/word_of_the_day.dart';
import '../players/family_widgets.dart';
import '../players/family_word.dart';
import '../players/player_summary.dart';
import '../players/players.dart';
import '../settings/word_level.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../ui/wordler_scaffold.dart';

// The screens for sharing one phone (spec-07): "Who's playing?", adding
// or editing a player, and the "Pass the phone" handover.

/// Everyone's summaries, keyed by player id.
Future<Map<String, PlayerSummary>> loadSummaries(List<Player> players, DateTime now) async =>
    {for (final p in players) p.id: await PlayerSummary.load(p, now)};

/// Shown when the app opens with two or more players, and from Home's
/// Switch. Picking a player hands them the phone.
class WhoIsPlayingScreen extends ConsumerStatefulWidget {
  const WhoIsPlayingScreen({super.key});

  @override
  ConsumerState<WhoIsPlayingScreen> createState() => _WhoIsPlayingScreenState();
}

class _WhoIsPlayingScreenState extends ConsumerState<WhoIsPlayingScreen> {
  Map<String, PlayerSummary> _summaries = const {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final summaries = await loadSummaries(ref.read(playersProvider).players, DateTime.now());
    if (mounted) setState(() => _summaries = summaries);
  }

  Future<void> _pick(Player player) async {
    await ref.read(playersProvider.notifier).select(player.id);
    ref.read(playerPickedProvider.notifier).state = true;
  }

  Future<void> _add() async {
    await Navigator.of(context).push(MaterialPageRoute<Player>(builder: (_) => const AddPlayerScreen()));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playersProvider);
    final now = DateTime.now();
    final family = ref.watch(familyWordProvider.notifier).today(now);
    ref.watch(familyWordProvider);
    final words = ref.watch(wordsOfTheDayProvider).valueOrNull;
    final played = players.players.where((p) => _summaries[p.id]?.playedToday ?? false).length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        backgroundColor: WColors.paper,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(WSize.screenPadding),
            children: [
              const SizedBox(height: WSize.gap3),
              Semantics(
                header: true,
                child: const Text("Who's playing?", style: WText.heading, textAlign: TextAlign.center),
              ),
              const SizedBox(height: WSize.gap4),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
                children: [
                  for (final p in players.players)
                    _PlayerTile(player: p, summary: _summaries[p.id], onTap: () => _pick(p)),
                ],
              ),
              const SizedBox(height: WSize.gap3),
              if (players.canAdd)
                ChunkyButton(label: 'Add a player', kind: ChunkyKind.secondary, expand: true, onPressed: _add),
              if (words != null && words.isNotEmpty) ...[
                const SizedBox(height: WSize.gap4),
                ChunkyCard(
                  color: WColors.skyTint,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("TODAY'S FAMILY WORD", style: WText.label.copyWith(color: WColors.ink)),
                      const SizedBox(height: 4),
                      FamilyWordSlots(
                        word: familyWordFor(now, words).word,
                        data: family,
                        players: players,
                        tileSize: 32,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        family.solved ? 'Found together!' : '$played of ${players.players.length} have played',
                        style: WText.bodyBold.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.summary, required this.onTap});

  final Player player;
  final PlayerSummary? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final status = summary == null ? '' : (summary.playedToday ? 'Played today' : 'Not yet today');
    return Semantics(
      button: true,
      label: '${player.name}. ${summary?.level.info.name ?? ''}. $status',
      excludeSemantics: true,
      child: ChunkyCard(
        hero: true,
        onTap: onTap,
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAvatar(player: player, size: 64),
              const SizedBox(height: 6),
              Text(player.name, style: WText.heading.copyWith(fontSize: 22)),
              Text(summary?.level.info.name ?? ' ', style: WText.bodyBold.copyWith(fontSize: 14)),
              Text(status.isEmpty ? ' ' : status, style: WText.label),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add a player, or (with [editing]) change a player's name and color.
/// Pops with the new player when one was added.
class AddPlayerScreen extends ConsumerStatefulWidget {
  const AddPlayerScreen({super.key, this.editing});

  final Player? editing;

  @override
  ConsumerState<AddPlayerScreen> createState() => _AddPlayerScreenState();
}

class _AddPlayerScreenState extends ConsumerState<AddPlayerScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.editing?.name ?? '');
  late int _color = widget.editing?.colorIndex ?? _firstFreeColor();
  WordLevel _level = WordLevel.explorer;

  int _firstFreeColor() {
    final used = {for (final p in ref.read(playersProvider).players) p.colorIndex};
    for (int i = 0; i < kPlayerColors.length; i++) {
      if (!used.contains(i)) return i;
    }
    return 0;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final controller = ref.read(playersProvider.notifier);
    final editing = widget.editing;
    if (editing != null) {
      await controller.update(editing.id, name: name, colorIndex: _color);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final player = await controller.add(name: name, colorIndex: _color, level: _level);
    if (mounted) Navigator.of(context).pop(player);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    final name = _name.text.trim();
    final preview = Player(id: 'preview', name: name, colorIndex: _color);
    return WordlerScaffold(
      title: editing == null ? 'Add a player' : 'Change player',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(WSize.screenPadding),
              children: [
                Center(child: PlayerAvatar(player: preview, size: 84)),
                const SizedBox(height: WSize.gap3),
                const Text('NAME', style: WText.label),
                const SizedBox(height: 4),
                TextField(
                  controller: _name,
                  maxLength: 12,
                  textCapitalization: TextCapitalization.words,
                  style: WText.bodyBold.copyWith(fontSize: 20),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Name',
                    filled: true,
                    fillColor: WColors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(WSize.radiusButton),
                      borderSide: const BorderSide(color: WColors.ink, width: WSize.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(WSize.radiusButton),
                      borderSide: const BorderSide(color: WColors.grass, width: WSize.outline + 1),
                    ),
                  ),
                ),
                const SizedBox(height: WSize.gap3),
                const Text('COLOR', style: WText.label),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (int i = 0; i < kPlayerColors.length; i++)
                      Semantics(
                        button: true,
                        selected: i == _color,
                        label: 'Color ${i + 1}',
                        child: GestureDetector(
                          onTap: () => setState(() => _color = i),
                          child: Container(
                            width: WSize.tapTarget,
                            height: WSize.tapTarget,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: i == _color ? WColors.ink : Colors.transparent,
                                width: WSize.outline,
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: kPlayerColors[i],
                                shape: BoxShape.circle,
                                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (editing == null) ...[
                  const SizedBox(height: WSize.gap3),
                  const Text('WORD LEVEL', style: WText.label),
                  const SizedBox(height: 6),
                  for (final level in WordLevel.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: WSize.gap2),
                      child: Semantics(
                        button: true,
                        selected: level == _level,
                        label: '${level.info.name}. ${level.info.goodFor}',
                        excludeSemantics: true,
                        child: ChunkyCard(
                          color: level == _level ? WColors.sun : WColors.card,
                          onTap: () => setState(() => _level = level),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(child: Text(level.info.name, style: WText.button.copyWith(color: WColors.ink))),
                              Text(level.info.goodFor.replaceFirst('Good for ', ''),
                                  style: WText.label.copyWith(color: WColors.ink)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: WSize.gap2),
                  Text(
                    '${name.isEmpty ? 'They get' : '$name gets'} their own village, coins and puzzles. '
                    'Nothing is sent anywhere: it all stays on this phone.',
                    style: WText.label,
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 0, WSize.screenPadding, WSize.screenPadding),
              child: ChunkyButton(
                label: editing == null ? (name.isEmpty ? 'Add player' : 'Add $name') : 'Save',
                size: ChunkySize.big,
                expand: true,
                onPressed: name.isEmpty ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The handover: a whole screen saying whose turn it is, so nobody sees
/// another player's puzzle or village by accident.
class PassPhoneScreen extends ConsumerWidget {
  const PassPhoneScreen({super.key, required this.player, this.summary});

  final Player player;
  final PlayerSummary? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = summary?.level.info.name;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: wordlerOverlayStyle,
      child: Scaffold(
        backgroundColor: WColors.paper,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(WSize.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(child: PlayerAvatar(player: player, size: 120)),
                const SizedBox(height: WSize.gap4),
                Text('Pass the phone to ${player.name}', style: WText.heading, textAlign: TextAlign.center),
                if (level != null) ...[
                  const SizedBox(height: WSize.gap2),
                  Text(
                    summary!.playedToday
                        ? '${player.name} has already played today.'
                        : '${player.name} has a $level puzzle today. It will find letters of the family word.',
                    style: WText.body,
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
                ChunkyButton(
                  label: "I'm ${player.name}",
                  size: ChunkySize.big,
                  expand: true,
                  onPressed: () async {
                    await ref.read(playersProvider.notifier).select(player.id);
                    ref.read(playerPickedProvider.notifier).state = true;
                    if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
                const SizedBox(height: WSize.gap2),
                ChunkyButton(
                  label: 'Not now',
                  kind: ChunkyKind.secondary,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
