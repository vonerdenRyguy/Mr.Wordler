import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily/daily_seed.dart' show dailyDateKey;
import '../game/letter_tile.dart';
import '../online/family_online_controller.dart';
import '../online/family_online_models.dart';
import '../online/helping.dart';
import '../players/player_summary.dart';
import '../players/players.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import '../ui/wordler_scaffold.dart';
import 'family_word_online_screens.dart' show memberColor;

// Helping each other (spec-10): give a letter, ask the family for one, and
// send a cheer. Letters go to the village rack, never the Daily. Cheers are
// stickers: nothing is ever typed.

Player _asPlayer(OnlineMember m) => Player(id: m.uid, name: m.name, colorIndex: m.colorIndex);

void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(text, style: WText.bodyBold.copyWith(color: WColors.white)),
    ));
}

/// Help buttons on someone's plot: their open request, Give a letter, and
/// Cheer!. On your own plot: Ask for a letter.
class PlotHelp extends ConsumerWidget {
  const PlotHelp({super.key, required this.member});

  final OnlineMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    final controller = ref.read(familyOnlineProvider.notifier);
    final today = dailyDateKey(DateTime.now());
    final isMe = member.uid == online.account?.uid;
    if (isMe) {
      final open = controller.myOpenRequest;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (open != null) ...[
          ChunkyCard(
            color: WColors.sunTint,
            child: Row(children: [
              SizedBox(width: 44, height: 50, child: LetterTile(letter: open)),
              const SizedBox(width: WSize.gap3),
              Expanded(child: Text('You asked the family for $open today.', style: WText.body)),
            ]),
          ),
          const SizedBox(height: WSize.gap3),
        ],
        ChunkyButton(
          label: open == null ? 'Ask for a letter' : 'Ask for a different letter',
          kind: ChunkyKind.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AskLetterScreen())),
        ),
      ]);
    }
    final wants = openRequest(member, online.notes, today);
    final left = controller.giftsLeftToday;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (wants != null) ...[
        ChunkyCard(
          color: WColors.sunTint,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${member.name.toUpperCase()} IS LOOKING FOR', style: WText.label.copyWith(color: WColors.ink)),
            const SizedBox(height: WSize.gap2),
            Row(children: [
              SizedBox(width: 44, height: 50, child: LetterTile(letter: wants)),
              const SizedBox(width: WSize.gap3),
              Expanded(child: Text('${member.name} asked the family for ${_article(wants)} $wants.', style: WText.body)),
            ]),
            const SizedBox(height: WSize.gap3),
            ChunkyButton(
              label: left > 0 ? 'Send ${member.name} ${_article(wants)} $wants' : 'No letters left today',
              expand: true,
              onPressed: left > 0 ? () => sendLetter(context, ref, member, wants) : null,
            ),
          ]),
        ),
        const SizedBox(height: WSize.gap3),
      ],
      Row(children: [
        Expanded(
          child: ChunkyButton(
            label: 'Give a letter',
            kind: ChunkyKind.secondary,
            onPressed: left > 0
                ? () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => GiveLetterScreen(uid: member.uid)))
                : null,
          ),
        ),
        const SizedBox(width: WSize.gap3),
        Expanded(
          child: ChunkyButton(
            label: 'Cheer!',
            kind: ChunkyKind.mode,
            modeColor: WColors.sun,
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CheerScreen(uid: member.uid))),
          ),
        ),
      ]),
      const SizedBox(height: WSize.gap2),
      Text(
        left == 0 ? 'No letters left to give today. More tomorrow!' : '$left letter${left == 1 ? '' : 's'} left to give today',
        style: WText.label,
        textAlign: TextAlign.center,
      ),
    ]);
  }
}

String _article(String letter) => 'AEFHILMNORSX'.contains(letter) ? 'an' : 'a';

/// Sends [letter] to [to] and says how it went.
Future<void> sendLetter(BuildContext context, WidgetRef ref, OnlineMember to, String letter) async {
  final ok = await ref.read(familyOnlineProvider.notifier).giveLetter(to.uid, letter);
  if (!context.mounted) return;
  if (ok) HapticFeedback.lightImpact();
  _say(context, ok ? 'Sent ${to.name} ${_article(letter)} $letter!' : "Couldn't send it. Check the internet and try again.");
}

/// A big A-Z grid to pick one letter.
class LetterPicker extends StatelessWidget {
  const LetterPicker({super.key, required this.selected, required this.onPick});

  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (final l in letters.split(''))
          Semantics(
            button: true,
            selected: l == selected,
            label: l,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onPick(l),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: WColors.ink, width: l == selected ? 4 : 0),
                ),
                child: LetterTile(letter: l, faceColor: l == selected ? WColors.sun : null),
              ),
            ),
          ),
      ],
    );
  }
}

class GiveLetterScreen extends ConsumerStatefulWidget {
  const GiveLetterScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<GiveLetterScreen> createState() => _GiveLetterScreenState();
}

class _GiveLetterScreenState extends ConsumerState<GiveLetterScreen> {
  String? _letter;
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(familyOnlineProvider);
    final to = online.family?.member(widget.uid);
    final left = ref.read(familyOnlineProvider.notifier).giftsLeftToday;
    if (to == null) return const WordlerScaffold(title: 'Give a letter', body: SizedBox.shrink());
    final letter = _letter;
    return WordlerScaffold(
      title: 'Give ${to.name} a letter',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          Text(
            "Pick any letter. It lands in ${to.name}'s village rack the next time they visit. It's free.",
            style: WText.body,
          ),
          const SizedBox(height: WSize.gap3),
          LetterPicker(selected: letter, onPick: (l) => setState(() => _letter = l)),
          const SizedBox(height: WSize.gap3),
          Text(
            left == 0
                ? 'No letters left to give today. More tomorrow!'
                : letter == null
                    ? '$left letter${left == 1 ? '' : 's'} left to give today'
                    : '${left - 1} left after this one today',
            style: WText.label,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyButton(
            label: letter == null ? 'Pick a letter' : 'Send the $letter',
            expand: true,
            size: ChunkySize.big,
            onPressed: letter == null || left == 0 || _sending
                ? null
                : () async {
                    setState(() => _sending = true);
                    await sendLetter(context, ref, to, letter);
                    if (context.mounted) Navigator.of(context).pop();
                  },
          ),
        ],
      ),
    );
  }
}

class AskLetterScreen extends ConsumerStatefulWidget {
  const AskLetterScreen({super.key});

  @override
  ConsumerState<AskLetterScreen> createState() => _AskLetterScreenState();
}

class _AskLetterScreenState extends ConsumerState<AskLetterScreen> {
  String? _letter;
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final letter = _letter;
    return WordlerScaffold(
      title: 'Ask for a letter',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          const Text('Stuck in your village? Ask the family. Anyone can send it.', style: WText.body),
          const SizedBox(height: WSize.gap3),
          LetterPicker(selected: letter, onPick: (l) => setState(() => _letter = l)),
          const SizedBox(height: WSize.gap3),
          ChunkyCard(
            color: WColors.sunTint,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                letter == null ? 'Pick the letter you need.' : '"I\'m looking for ${_article(letter)} $letter"',
                style: WText.heading.copyWith(fontSize: 20),
              ),
              const SizedBox(height: WSize.gap1),
              const Text(
                'The family sees this on your plot and on their Home until someone sends one, or until tomorrow.',
                style: WText.label,
              ),
            ]),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyButton(
            label: 'Ask the family',
            expand: true,
            size: ChunkySize.big,
            onPressed: letter == null || _sending
                ? null
                : () async {
                    setState(() => _sending = true);
                    final ok = await ref.read(familyOnlineProvider.notifier).askFor(letter);
                    if (!context.mounted) return;
                    _say(context, ok ? 'Asked the family for ${_article(letter)} $letter.' : "Couldn't ask. Check the internet and try again.");
                    Navigator.of(context).pop();
                  },
          ),
        ],
      ),
    );
  }
}

/// One sticker: a big picture with a word or two.
class StickerTile extends StatelessWidget {
  const StickerTile({super.key, required this.sticker, this.selected = false, this.onTap, this.size = 104});

  final Sticker sticker;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: sticker.word,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: size,
          decoration: BoxDecoration(
            color: selected ? WColors.sunTint : WColors.card,
            borderRadius: BorderRadius.circular(WSize.radiusCard),
            border: Border.all(color: WColors.ink, width: selected ? 5 : WSize.outline),
            boxShadow: const [BoxShadow(color: WColors.ink, offset: Offset(0, 4))],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(sticker.glyph, style: TextStyle(fontSize: size * 0.38), textScaler: TextScaler.noScaling),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text(sticker.word, style: WText.heading.copyWith(fontSize: 18))),
          ]),
        ),
      ),
    );
  }
}

class CheerScreen extends ConsumerStatefulWidget {
  const CheerScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<CheerScreen> createState() => _CheerScreenState();
}

class _CheerScreenState extends ConsumerState<CheerScreen> {
  String? _sticker;
  bool _sending = false;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(familyOnlineProvider);
    final to = online.family?.member(widget.uid);
    if (to == null) return const WordlerScaffold(title: 'Cheer', body: SizedBox.shrink());
    final picked = stickerById(_sticker);
    // The newest building gets the cheer, if one went up today.
    final today = dailyDateKey(DateTime.now());
    final about = to.newOnDay(today).lastOrNull;
    const perPage = 6;
    final pages = (kStickers.length / perPage).ceil();
    return WordlerScaffold(
      title: 'Cheer for ${to.name}',
      body: Padding(
        padding: const EdgeInsets.all(WSize.screenPadding),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Tap a sticker. ${to.name} sees it with your name.', style: WText.body),
          const SizedBox(height: WSize.gap3),
          Expanded(
            child: PageView.builder(
              itemCount: pages,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, p) => GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.45,
                padding: const EdgeInsets.only(bottom: 6),
                children: [
                  for (final s in kStickers.skip(p * perPage).take(perPage))
                    StickerTile(sticker: s, selected: s.id == _sticker, onTap: () => setState(() => _sticker = s.id)),
                ],
              ),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (int i = 0; i < pages; i++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page ? WColors.ink : WColors.card,
                  border: Border.all(color: WColors.ink, width: 2),
                ),
              ),
          ]),
          const Text('Swipe for more stickers.', style: WText.label, textAlign: TextAlign.center),
          const SizedBox(height: WSize.gap3),
          ChunkyButton(
            label: picked == null ? 'Pick a sticker' : 'Send ${picked.word}',
            expand: true,
            size: ChunkySize.big,
            onPressed: picked == null || _sending
                ? null
                : () async {
                    setState(() => _sending = true);
                    final ok = await ref.read(familyOnlineProvider.notifier).cheer(to.uid, picked.id, about: about);
                    if (!context.mounted) return;
                    if (ok) HapticFeedback.lightImpact();
                    _say(context, ok ? 'Sent ${picked.word} to ${to.name}!' : "Couldn't send it. Check the internet and try again.");
                    Navigator.of(context).pop();
                  },
          ),
        ]),
      ),
    );
  }
}

// ---- From your family (Home) -------------------------------------------------

String _aboutText(String? about) {
  if (about == null) return '';
  if (about == 'family word') return ' for the family word';
  return ' for your ${about.toUpperCase()}';
}

/// One line: a gift, a cheer, or someone's request with a Send button.
class HelpItemRow extends ConsumerWidget {
  const HelpItemRow({super.key, required this.item, required this.family});

  final HelpItem item;
  final OnlineFamily family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = item.note;
    final who = note != null ? family.member(note.from) : item.asker;
    final name = who?.name ?? 'Someone';
    final Widget text;
    final Widget trailing;
    if (note == null) {
      final letter = item.letter!;
      text = Text.rich(TextSpan(style: WText.body, children: [
        TextSpan(text: name, style: WText.bodyBold),
        TextSpan(text: ' is looking for ${_article(letter)} '),
        TextSpan(text: letter, style: WText.bodyBold),
      ]));
      final left = ref.read(familyOnlineProvider.notifier).giftsLeftToday;
      trailing = ChunkyButton(
        label: 'Send',
        size: ChunkySize.small,
        onPressed: left > 0 && who != null ? () => sendLetter(context, ref, who, letter) : null,
      );
    } else if (note.kind == NoteKind.gift) {
      text = Text.rich(TextSpan(style: WText.body, children: [
        TextSpan(text: name, style: WText.bodyBold),
        TextSpan(text: ' sent you ${_article(note.letter!)} '),
        TextSpan(text: note.letter, style: WText.bodyBold),
      ]));
      trailing = SizedBox(width: 40, height: 46, child: LetterTile(letter: note.letter!));
    } else {
      final s = stickerById(note.sticker);
      text = Text.rich(TextSpan(style: WText.body, children: [
        TextSpan(text: name, style: WText.bodyBold),
        TextSpan(text: ': ${s?.word ?? 'Cheers!'}${_aboutText(note.about)}'),
      ]));
      trailing = Text(s?.glyph ?? '⭐', style: const TextStyle(fontSize: 30), textScaler: TextScaler.noScaling);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        if (who != null) PlayerAvatar(player: _asPlayer(who), size: 36),
        const SizedBox(width: WSize.gap2),
        Expanded(child: text),
        const SizedBox(width: WSize.gap2),
        trailing,
      ]),
    );
  }
}

/// Today's and yesterday's gifts, cheers and requests for this player.
List<HelpItem> myHelpItems(FamilyOnlineState online) {
  final family = online.family;
  final uid = online.account?.uid;
  if (family == null || uid == null) return const [];
  return helpItemsFor(uid: uid, members: family.members, notes: online.notes, dayKey: dailyDateKey(DateTime.now()));
}

/// The compact Home card: the newest item, and how many more.
class FromFamilyCard extends ConsumerWidget {
  const FromFamilyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    final family = online.family;
    final items = myHelpItems(online);
    if (family == null || items.isEmpty) return const SizedBox.shrink();
    final waiting = ref.read(familyOnlineProvider.notifier).waitingGiftsForMe.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChunkyCard(
        color: WColors.sunTint,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FromFamilyScreen())),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('FROM YOUR FAMILY', style: WText.label.copyWith(color: WColors.ink))),
            if (items.length > 1) Text('+${items.length - 1} more', style: WText.label.copyWith(color: WColors.ink)),
          ]),
          HelpItemRow(item: items.first, family: family),
          if (waiting > 0)
            Text(
              '$waiting gift${waiting == 1 ? '' : 's'} waiting: ${waiting == 1 ? 'it goes' : 'they go'} in your rack when you visit your village.',
              style: WText.label,
            ),
        ]),
      ),
    );
  }
}

class FromFamilyScreen extends ConsumerWidget {
  const FromFamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    final family = online.family;
    final items = myHelpItems(online);
    final left = ref.read(familyOnlineProvider.notifier).giftsLeftToday;
    return WordlerScaffold(
      title: 'From your family',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          if (family == null || items.isEmpty)
            const ChunkyCard(child: Text('Nothing yet today. Gifts and cheers from your family show up here.', style: WText.body))
          else
            ChunkyCard(
              child: Column(children: [for (final i in items) HelpItemRow(item: i, family: family)]),
            ),
          const SizedBox(height: WSize.gap3),
          Text(
            left == 0 ? 'No letters left to give today.' : '$left letter${left == 1 ? '' : 's'} left to give today',
            style: WText.label,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyButton(
            label: 'Ask for a letter',
            kind: ChunkyKind.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AskLetterScreen())),
          ),
          const SizedBox(height: WSize.gap3),
          const Text(
            'Only stickers and letters: there is no chat, and nothing goes outside the family.',
            style: WText.label,
          ),
        ],
      ),
    );
  }
}

// ---- Gifts arriving in the village -------------------------------------------

/// Says who sent the gifts that just landed in the rack, with Say thank
/// you (a Thank you! sticker to each sender).
Future<void> showGiftsArrived(BuildContext context, WidgetRef ref, List<FamilyNote> gifts) async {
  final family = ref.read(familyOnlineProvider).family;
  if (gifts.isEmpty || family == null) return;
  final senders = <String>{for (final g in gifts) g.from};
  String nameOf(String uid) => family.member(uid)?.name ?? 'Someone';
  final title = gifts.length == 1
      ? '${nameOf(gifts.first.from)} sent you ${_article(gifts.first.letter!)} ${gifts.first.letter}!'
      : 'Your family sent you ${gifts.length} letters!';
  final lines = gifts.length == 1 ? '' : '${[for (final g in gifts) '${g.letter} from ${nameOf(g.from)}'].join(', ')}. ';
  await showWordlerDialog<void>(
    context,
    title: title,
    icon: const Text('\u{1F381}', style: TextStyle(fontSize: 34), textScaler: TextScaler.noScaling),
    bodyText: "${lines}It's in your rack with a gold stripe, on top of your 10 letters.",
    actions: [
      WordlerDialogAction('Say thank you', () async {
        final c = ref.read(familyOnlineProvider.notifier);
        for (final uid in senders) {
          await c.cheer(uid, kThankYouSticker);
        }
      }),
      WordlerDialogAction('Lovely!', () {}, kind: ChunkyKind.secondary),
    ],
  );
}

/// A member's color, for gift stripes.
Color? senderColor(OnlineFamily? family, String uid) {
  final m = family?.member(uid);
  return m == null ? null : memberColor(m);
}
