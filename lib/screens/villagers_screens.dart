import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../explore/island_map.dart';
import '../settings/word_level.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/reward_moment.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import '../ui/wordler_scaffold.dart';
import '../village/village_cards.dart' show showVillageSheet;
import '../villagers/village_book.dart';
import '../villagers/villager_look.dart';
import '../villagers/villager_names.dart';
import '../villagers/wish.dart';

// Everything the player sees about villagers (spec-16): the move-in moment
// and naming sheet (N162), the villager card (N164), the wish-came-true
// moment (N165) and the Your villagers page (N166).

/// What the village screen offers the villager screens. The screen owns the
/// book (it is saved with the village); these widgets only listen to it.
abstract class VillagerHost {
  ValueListenable<VillagerBook> get villagerBook;
  WordLevel get wordLevel;
  IslandMap get islandMap;

  void renameVillager(String id, String name);

  /// Swaps the villager's open wish for a new one (free, any time).
  void differentWish(String id);

  /// Jumps the village to this villager; the caller closes its own page first.
  void findVillager(String id);

  /// Opens a villager's card (from the page).
  void openVillagerCard(String id);
}

// ── Move-in ──────────────────────────────────────────────────────────────────

/// The "Someone moved in!" moment, then the naming sheet. Returns the name
/// chosen (the ready name if they just press Welcome home).
Future<String> showMoveIn(
  BuildContext context, {
  required Villager villager,
  required String word,
  required List<String> nameChoices,
}) async {
  await showRewardMoment(
    context,
    ribbon: 'Someone moved in!',
    title: 'A new villager!',
    message: 'Your word $word reached them. They\'ll walk along your words from now on.',
    picture: VillagerFace(id: villager.id, name: nameChoices.first, size: 96),
    buttonLabel: 'Meet them',
  );
  if (!context.mounted) return nameChoices.first;
  final name = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => NameVillagerDialog(villager: villager, choices: nameChoices),
  );
  return name ?? nameChoices.first;
}

/// Pick one of the ready names or type any name (kids can type anything).
class NameVillagerDialog extends StatefulWidget {
  const NameVillagerDialog({super.key, required this.villager, required this.choices, this.title = 'What\'s their name?'});

  final Villager villager;
  final List<String> choices;
  final String title;

  @override
  State<NameVillagerDialog> createState() => _NameVillagerDialogState();
}

class _NameVillagerDialogState extends State<NameVillagerDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.choices.first);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => cleanVillagerName(_controller.text) ?? widget.choices.first;

  @override
  Widget build(BuildContext context) {
    final wish = widget.villager.wish;
    return WordlerDialog(
      title: widget.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: VillagerFace(id: widget.villager.id, name: _name, size: 72)),
          const SizedBox(height: WSize.gap3),
          Text('Their name', style: WText.label),
          const SizedBox(height: WSize.gap1),
          TextField(
            controller: _controller,
            maxLength: kMaxVillagerNameLength,
            textCapitalization: TextCapitalization.words,
            style: WText.buttonBig,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: WColors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(WSize.radiusButton),
                borderSide: const BorderSide(color: WColors.ink, width: WSize.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(WSize.radiusButton),
                borderSide: const BorderSide(color: WColors.ink, width: WSize.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(WSize.radiusButton),
                borderSide: const BorderSide(color: WColors.ink, width: WSize.outline + 1),
              ),
            ),
          ),
          const SizedBox(height: WSize.gap2),
          Wrap(
            spacing: WSize.gap2,
            runSpacing: WSize.gap2,
            children: [
              for (final n in widget.choices)
                ChunkyButton(
                  label: n,
                  size: ChunkySize.small,
                  kind: _controller.text == n ? ChunkyKind.mode : ChunkyKind.secondary,
                  modeColor: WColors.sun,
                  onPressed: () => setState(() => _controller.text = n),
                ),
            ],
          ),
          if (wish != null) ...[
            const SizedBox(height: WSize.gap3),
            Text('$_name\'s first wish', style: WText.label),
            const SizedBox(height: WSize.gap1),
            Text('"${_capitalize(wish.describe())}." Spell it anywhere in your village. No hurry.', style: WText.bodyBold),
          ],
        ],
      ),
      actions: [WordlerDialogAction('Welcome home, $_name!', () => Navigator.of(context).pop(_name))],
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// A single text box to rename a villager.
Future<String?> showRenameVillager(BuildContext context, Villager villager) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(villager: villager),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.villager});
  final Villager villager;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.villager.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WordlerDialog(
      title: 'Rename ${widget.villager.name}',
      body: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: kMaxVillagerNameLength,
        textCapitalization: TextCapitalization.words,
        style: WText.buttonBig,
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: WColors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(WSize.radiusButton),
            borderSide: const BorderSide(color: WColors.ink, width: WSize.outline),
          ),
        ),
      ),
      actions: [
        WordlerDialogAction('Save name', () => Navigator.of(context).pop(cleanVillagerName(_controller.text))),
        WordlerDialogAction('Cancel', () => Navigator.of(context).pop(), kind: ChunkyKind.secondary),
      ],
    );
  }
}

// ── A wish comes true ────────────────────────────────────────────────────────

/// The reward moment for a wish that came true. The coins must already be
/// paid (the moment's rule); [g] says how many.
Future<void> showWishGranted(BuildContext context, WishGranted g) {
  final v = g.villager;
  final lines = <String>[
    '${v.name} wished for ${g.wish.describe()}, and ${g.word} did it.',
    if (g.becameBestFriend) '${v.name} is now your best friend and brought a present!',
    '+1 heart  ·  +${g.xp} XP${g.becameBestFriend ? '  ·  +$kBestFriendCoins present' : ''}',
    if (!g.becameBestFriend) 'A new wish comes tomorrow.',
  ];
  return showRewardMoment(
    context,
    ribbon: g.becameBestFriend ? 'Best friends!' : 'Wish came true!',
    title: g.becameBestFriend ? '${v.name} loves your village' : '${v.name} is happy!',
    message: lines.join('\n'),
    coins: g.coins,
    picture: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        VillagerFace(id: v.id, name: v.name, size: 80, happy: g.becameBestFriend),
        const SizedBox(height: 6),
        Hearts(filled: v.hearts, size: 26),
      ],
    ),
    buttonLabel: 'Hooray!',
  );
}

// ── The card (N164) ──────────────────────────────────────────────────────────

Future<void> showVillagerCard(BuildContext context, VillagerHost host, String id) =>
    showVillageSheet<void>(context, VillagerCard(host: host, id: id));

class VillagerCard extends StatefulWidget {
  const VillagerCard({super.key, required this.host, required this.id});

  final VillagerHost host;
  final String id;

  @override
  State<VillagerCard> createState() => _VillagerCardState();
}

class _VillagerCardState extends State<VillagerCard> {
  // Another idea: 0 = none yet, 1 = first letters, 2 = the whole word,
  // and every press after that is a different word, whole.
  int _ideas = 0;
  int _ideaRound = 0;
  Wish? _ideaFor;
  final _rng = math.Random();

  String? _idea(Villager v) {
    final wish = v.wish;
    if (wish == null) return null;
    final minLetters = wish.kind == WishKind.place ? 4 : 3;
    return exampleWord(wish, widget.host.wordLevel, math.Random(Object.hash(v.id, wish, _ideaRound)), minLetters: minLetters);
  }

  void _anotherIdea(Villager v) {
    setState(() {
      if (_ideaFor != v.wish) {
        _ideaFor = v.wish;
        _ideas = 0;
        _ideaRound = _rng.nextInt(1 << 20);
      }
      if (_ideas >= 2) _ideaRound = _rng.nextInt(1 << 20);
      _ideas++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VillagerBook>(
      valueListenable: widget.host.villagerBook,
      builder: (context, book, _) {
        final v = book.byId(widget.id);
        if (v == null) return const SizedBox.shrink();
        if (_ideaFor != v.wish) {
          _ideas = 0;
          _ideaFor = v.wish;
        }
        final wish = v.wish;
        final idea = _ideas > 0 ? _idea(v) : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                VillagerFace(id: v.id, name: v.name, size: 72, happy: v.bestFriend),
                const SizedBox(width: WSize.gap3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(v.name, style: WText.title.copyWith(fontSize: 30), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          ChunkyButton(
                            label: 'Rename',
                            size: ChunkySize.small,
                            kind: ChunkyKind.secondary,
                            onPressed: () async {
                              final name = await showRenameVillager(context, v);
                              if (name != null) widget.host.renameVillager(v.id, name);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        Hearts(filled: v.hearts),
                        const SizedBox(width: 6),
                        Flexible(child: Text(v.bestFriend ? 'Best friend' : 'Friends', style: WText.label)),
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (v.movedInWord.isNotEmpty) 'Moved in near ${v.movedInWord}',
                          '${v.granted} ${v.granted == 1 ? 'wish' : 'wishes'} granted',
                        ].join(' · '),
                        style: WText.label,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: WSize.gap3),
            ChunkyCard(
              color: WColors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wish == null ? '${v.name} is happy!' : '${v.name} wishes for', style: WText.label),
                  const SizedBox(height: 4),
                  if (wish != null) ...[
                    Text(_capitalize(wish.describe()), style: WText.heading.copyWith(fontSize: 26)),
                    const SizedBox(height: 4),
                    Text(
                      wish.kind == WishKind.place && wish.place == Wish.nearMe
                          ? 'Spell it close to where ${v.name} moved in.'
                          : 'Spell it anywhere in your village. It doesn\'t need to touch ${v.name}.',
                      style: WText.label,
                    ),
                    if (idea != null) ...[
                      const SizedBox(height: WSize.gap2),
                      _IdeaTiles(word: idea, showAll: _ideas >= 2),
                    ],
                  ] else
                    Text('A new wish comes tomorrow.', style: WText.heading.copyWith(fontSize: 22)),
                ],
              ),
            ),
            const SizedBox(height: WSize.gap3),
            Row(
              children: [
                Expanded(
                  child: ChunkyButton(
                    label: 'Another idea',
                    kind: ChunkyKind.mode,
                    modeColor: WColors.sun,
                    expand: true,
                    onPressed: wish == null ? null : () => _anotherIdea(v),
                  ),
                ),
                const SizedBox(width: WSize.gap2),
                Expanded(
                  child: ChunkyButton(
                    label: 'Different wish',
                    kind: ChunkyKind.secondary,
                    expand: true,
                    onPressed: wish == null ? null : () => widget.host.differentWish(v.id),
                  ),
                ),
              ],
            ),
            const SizedBox(height: WSize.gap2),
            ChunkyButton(
              label: wish == null ? 'OK' : 'OK, I\'ll try!',
              expand: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}

class _IdeaTiles extends StatelessWidget {
  const _IdeaTiles({required this.word, required this.showAll});

  final String word;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final letters = word.split('');
    return Semantics(
      label: showAll ? 'Idea: $word' : 'An idea starting with ${letters.first}',
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Idea:', style: WText.label),
          for (var i = 0; i < letters.length; i++)
            Container(
              width: 32,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: showAll || i == 0 ? WColors.tile : WColors.boardCell,
                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                showAll || i == 0 ? letters[i] : '?',
                textScaler: TextScaler.noScaling,
                style: WText.button.copyWith(color: showAll || i == 0 ? WColors.ink : WColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Your villagers (N166) ────────────────────────────────────────────────────

class VillagersPage extends StatelessWidget {
  const VillagersPage({super.key, required this.host});

  final VillagerHost host;

  /// "2 in the Forest, 3 in the Hills" for the villagers not met yet.
  static String fogSummary(IslandMap map, VillagerBook book) {
    final counts = <Ring, int>{};
    for (final s in map.villagers) {
      if (book.isMet(s.id)) continue;
      final ring = map.ringAtIndex(s.cell);
      counts[ring] = (counts[ring] ?? 0) + 1;
    }
    final rings = counts.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
    return [for (final r in rings) '${counts[r]} in the ${r.displayName}'].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VillagerBook>(
      valueListenable: host.villagerBook,
      builder: (context, book, _) {
        final total = host.islandMap.villagers.length;
        final unmet = total - book.count;
        final sorted = [...book.villagers]..sort((a, b) => a.id.compareTo(b.id));
        return WordlerScaffold(
          title: 'Your villagers',
          actions: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE8A3),
                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('${book.count} of $total', style: WText.buttonSmall),
            ),
          ],
          body: ListView(
            padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 4, WSize.screenPadding, WSize.screenPadding),
            children: [
              if (book.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: WSize.gap3),
                  child: Text(
                    'Nobody has moved in yet. Spell a word over a faint outline in your village to bring someone home.',
                    style: WText.body,
                  ),
                ),
              for (final v in sorted)
                Padding(
                  padding: const EdgeInsets.only(bottom: WSize.gap2),
                  child: _VillagerRow(
                    villager: v,
                    onOpen: () => host.openVillagerCard(v.id),
                    onFind: () {
                      Navigator.of(context).pop();
                      host.findVillager(v.id);
                    },
                  ),
                ),
              if (unmet > 0) ...[
                const SizedBox(height: WSize.gap2),
                Text('STILL OUT IN THE FOG', style: WText.label.copyWith(letterSpacing: 1.1)),
                const SizedBox(height: WSize.gap2),
                Semantics(
                  label: '$unmet villagers not met yet',
                  excludeSemantics: true,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < unmet; i++)
                        Container(
                          width: 34,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6DCC6),
                            border: Border.all(color: WColors.muted, width: WSize.outlineSmall),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16), bottom: Radius.circular(6)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: WSize.gap2),
                Text(fogSummary(host.islandMap, book), style: WText.bodyBold.copyWith(color: WColors.muted)),
              ],
              const SizedBox(height: WSize.gap4),
              Text(
                'Wishes never run out of time. Tap a villager to change their wish or get an idea.',
                textAlign: TextAlign.center,
                style: WText.label,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VillagerRow extends StatelessWidget {
  const _VillagerRow({required this.villager, required this.onOpen, required this.onFind});

  final Villager villager;
  final VoidCallback onOpen;
  final VoidCallback onFind;

  @override
  Widget build(BuildContext context) {
    final v = villager;
    return ChunkyCard(
      color: v.bestFriend ? const Color(0xFFFFE0EA) : WColors.card,
      onTap: onOpen,
      child: Row(
        children: [
          VillagerFace(id: v.id, name: v.name, size: 52, happy: v.bestFriend),
          const SizedBox(width: WSize.gap3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.bestFriend ? '${v.name} · best friend' : v.name, style: WText.button),
                const SizedBox(height: 2),
                Text(
                  v.wish == null ? 'Happy. A new wish tomorrow.' : '"${_capitalize(v.wish!.describe())}."',
                  style: WText.bodyBold.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 4),
                Hearts(filled: v.hearts, size: 16),
              ],
            ),
          ),
          ChunkyButton(label: 'Find', size: ChunkySize.small, kind: ChunkyKind.secondary, onPressed: onFind),
        ],
      ),
    );
  }
}
