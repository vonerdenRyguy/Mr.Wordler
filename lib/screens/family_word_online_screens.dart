import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily/daily_challenge_controller.dart';
import '../daily/daily_seed.dart' show dailyDateKey;
import '../daily/word_of_the_day.dart';
import '../dictionary/word_speaker.dart';
import '../online/family_online_controller.dart';
import '../online/family_online_models.dart';
import '../players/family_widgets.dart';
import '../players/family_word.dart';
import '../players/player_summary.dart';
import '../players/players.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../ui/wordler_dialog.dart';
import '../ui/wordler_scaffold.dart';
import '../village/magic_word.dart';
import 'daily_challenge_screen.dart';

// The family word and the family map online (spec-09). Everyone in an online
// family, on every phone, shares one word a day; each person's finished
// Daily uncovers their own share, in any order, so the whole word needs
// everyone. The map shows each member's plot with their buildings.

Color memberColor(OnlineMember m) => kPlayerColors[m.colorIndex % kPlayerColors.length];

Player _asPlayer(OnlineMember m) => Player(id: m.uid, name: m.name, colorIndex: m.colorIndex);

/// Today's online family word as the tile row's data.
FamilyWordData familyWordDataOf(FamilyDay day) =>
    FamilyWordData(found: day.found, solved: day.solved, solvedEarly: day.solvedEarly, streak: day.streak);

/// The tile row for the online family word, striped in each finder's color.
class OnlineFamilyWordSlots extends ConsumerWidget {
  const OnlineFamilyWordSlots({super.key, required this.word, required this.day, required this.family, this.tileSize = 42});

  final String word;
  final FamilyDay day;
  final OnlineFamily family;
  final double tileSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FamilyWordSlots(
      word: word,
      data: familyWordDataOf(day),
      players: ref.watch(playersProvider),
      tileSize: tileSize,
      colorOf: (uid) {
        final m = family.member(uid);
        return m == null ? null : memberColor(m);
      },
    );
  }
}

class OnlineFamilyWordScreen extends ConsumerStatefulWidget {
  const OnlineFamilyWordScreen({super.key});

  @override
  ConsumerState<OnlineFamilyWordScreen> createState() => _OnlineFamilyWordScreenState();
}

class _OnlineFamilyWordScreenState extends ConsumerState<OnlineFamilyWordScreen> {
  /// uid -> player id, for members who share this phone.
  Map<String, String> _local = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(familyOnlineProvider.notifier).watchToday();
      claimFamilyCoins(ref, context);
    });
    FamilyOnlineController.localUids(ref.read(playersProvider).players).then((m) {
      if (mounted) setState(() => _local = m);
    });
  }

  Future<void> _play() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DailyChallengeScreen()));
    if (mounted) claimFamilyCoins(ref, context);
  }

  Future<void> _guess(String word) async {
    final input = TextEditingController();
    String? typed;
    await showWordlerDialog<void>(
      context,
      title: 'Guess the family word',
      body: TextField(
        controller: input,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: word.length,
        style: WText.button.copyWith(color: WColors.ink, letterSpacing: 2),
        decoration: const InputDecoration(hintText: 'Type the word'),
      ),
      actions: [
        WordlerDialogAction('Not yet', () {}, kind: ChunkyKind.secondary),
        WordlerDialogAction('Guess', () => typed = input.text),
      ],
    );
    final guess = typed;
    if (guess == null || guess.trim().isEmpty || !mounted) return;
    bool right;
    try {
      right = await ref.read(familyOnlineProvider.notifier).guess(text: guess, now: DateTime.now(), word: word);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't reach the family just now. Check the internet and try again.")),
        );
      }
      return;
    }
    if (!mounted) return;
    if (right) {
      claimFamilyCoins(ref, context);
    } else {
      showWordlerDialog<void>(
        context,
        title: 'Not that one',
        bodyText: 'Good try! Only you saw that guess. More letters come out as the family plays.',
        actions: [WordlerDialogAction('OK', () {})],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(familyOnlineProvider);
    // The word just got found (here or on another phone): collect the coins.
    ref.listen(familyOnlineProvider.select((s) => s.day?.solved ?? false), (was, now) {
      if (now && was != true) claimFamilyCoins(ref, context);
    });
    final family = online.family;
    final me = online.me;
    final words = ref.watch(wordsOfTheDayProvider).valueOrNull;
    if (family == null || me == null || words == null || words.isEmpty) {
      return const WordlerScaffold(title: "Today's family word", body: Center(child: CircularProgressIndicator()));
    }
    final now = DateTime.now();
    final entry = familyWordFor(now, words);
    final word = entry.word;
    final day = online.day ?? const FamilyDay();
    if (day.solved) return _OnlineFound(entry: entry, day: day, family: family, meUid: me.uid);

    ref.watch(dailyChallengeProvider);
    final mePlayed = ref.read(dailyChallengeProvider.notifier).hasPlayedToday(now);
    final today = dailyDateKey(now);
    return WordlerScaffold(
      title: "Today's family word",
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            _Pill(family.name, WColors.white),
            _Pill('Online: ${family.members.length} ${family.members.length == 1 ? 'person' : 'people'}', WColors.skyTint),
          ]),
          const SizedBox(height: WSize.gap3),
          ChunkyCard(
            color: WColors.skyTint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('THE HINT', style: WText.label.copyWith(color: WColors.ink)),
                const SizedBox(height: 4),
                Text(entry.meaning, style: WText.heading.copyWith(fontSize: 21)),
                const SizedBox(height: WSize.gap3),
                OnlineFamilyWordSlots(word: word, day: day, family: family),
                const SizedBox(height: WSize.gap2),
                Text(
                  '${day.revealed.length} of ${word.length} letters found. '
                  'The colored edge shows who found each one.',
                  style: WText.bodyBold.copyWith(fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                for (final m in family.members)
                  _OnlineMemberRow(
                    member: m,
                    isMe: m.uid == me.uid,
                    onThisPhone: m.uid != me.uid && _local.containsKey(m.uid),
                    letters: day.found[m.uid]?.map((i) => word[i]).toList(),
                    played: m.playedOn(today) || (m.uid == me.uid && mePlayed),
                  ),
              ],
            ),
          ),
          const SizedBox(height: WSize.gap3),
          const Text(
            "Play any time today, in any order. Each person's puzzle uncovers their own letters, so the whole word "
            'needs everyone. Guess early: +$kFamilyWordEarlyCoins coins each. All letters out: +$kFamilyWordCoins each.',
            style: WText.label,
          ),
          const SizedBox(height: WSize.gap3),
          if (!mePlayed)
            ChunkyButton(label: 'Play my puzzle', size: ChunkySize.big, expand: true, onPressed: _play),
          const SizedBox(height: WSize.gap2),
          ChunkyButton(
            label: 'We know it! Guess',
            kind: ChunkyKind.secondary,
            expand: true,
            onPressed: () => _guess(word),
          ),
          const SizedBox(height: WSize.gap2),
          ChunkyButton(
            label: 'The family map',
            kind: ChunkyKind.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FamilyMapScreen())),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(WSize.radiusChip),
        border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
      ),
      child: Text(text, style: WText.buttonSmall.copyWith(color: WColors.ink, fontSize: 15)),
    );
  }
}

class _OnlineMemberRow extends StatelessWidget {
  const _OnlineMemberRow({
    required this.member,
    required this.isMe,
    required this.onThisPhone,
    required this.letters,
    required this.played,
  });

  final OnlineMember member;
  final bool isMe;
  final bool onThisPhone;
  final List<String>? letters;
  final bool played;

  @override
  Widget build(BuildContext context) {
    final found = letters;
    final String status;
    if (found != null && found.isNotEmpty) {
      status = 'Found ${found.join(' and ')}';
    } else if (found != null || played) {
      status = 'Played today';
    } else if (isMe) {
      status = 'Your letters are waiting';
    } else {
      status = onThisPhone ? 'On this phone: letters waiting' : 'Letters waiting';
    }
    final done = found != null || played;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          PlayerAvatar(player: _asPlayer(member)),
          const SizedBox(width: WSize.gap2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isMe ? '${member.name} (you)' : member.name, style: WText.bodyBold),
                Text(status, style: WText.label),
              ],
            ),
          ),
          if (done)
            const Icon(Icons.check_circle, color: WColors.grass, size: 28)
          else
            const _Pill('Any time today', WColors.white),
        ],
      ),
    );
  }
}

class _OnlineFound extends ConsumerWidget {
  const _OnlineFound({required this.entry, required this.day, required this.family, required this.meUid});

  final WordOfDay entry;
  final FamilyDay day;
  final OnlineFamily family;
  final String meUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = day.solvedEarly ? kFamilyWordEarlyCoins : kFamilyWordCoins;
    final by = family.member(day.solvedBy ?? '');
    final who = by == null
        ? 'The family found it'
        : by.uid == meUid
            ? (day.solvedEarly ? 'You guessed it' : 'Your letters finished it')
            : (day.solvedEarly ? '${by.name} guessed it' : "${by.name}'s letters finished it");
    return WordlerScaffold(
      title: "Today's family word",
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          ChunkyCard(
            color: WColors.leafTint,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('FOUND!', style: WText.label.copyWith(color: WColors.ink)),
                const SizedBox(height: WSize.gap2),
                Center(child: OnlineFamilyWordSlots(word: entry.word, day: day, family: family, tileSize: 44)),
                const SizedBox(height: WSize.gap3),
                Text(entry.meaning, style: WText.body.copyWith(fontSize: 18), textAlign: TextAlign.center),
                const SizedBox(height: WSize.gap2),
                Text(who, style: WText.heading.copyWith(fontSize: 20), textAlign: TextAlign.center),
                const SizedBox(height: WSize.gap3),
                ChunkyButton(
                  label: 'Hear the word',
                  icon: Icons.volume_up,
                  kind: ChunkyKind.secondary,
                  expand: true,
                  onPressed: () => ref.read(wordSpeakerProvider).speak(entry.word),
                ),
              ],
            ),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('+$coins', style: WText.number.copyWith(color: WColors.grass)),
                  const SizedBox(width: WSize.gap3),
                  const Expanded(child: Text('coins for everyone in the family', style: WText.bodyBold)),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Yours are added on this phone. Everyone else gets theirs the next time they open the app.',
                  style: WText.label,
                ),
              ],
            ),
          ),
          if (day.streak >= 2) ...[
            const SizedBox(height: WSize.gap3),
            ChunkyCard(
              color: WColors.sunTint,
              child: Row(children: [
                const Expanded(child: Text('Family streak', style: WText.heading)),
                _Pill('${day.streak} days', WColors.sun),
              ]),
            ),
          ],
          const SizedBox(height: WSize.gap4),
          ChunkyButton(
            label: 'See the family map',
            expand: true,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FamilyMapScreen())),
          ),
          const SizedBox(height: WSize.gap3),
          const Text('Come back tomorrow for a new family word.', style: WText.label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ---- The family map ---------------------------------------------------------

String buildingSprite(String word) => 'assets/village/buildings/${word.toLowerCase()}.png';

String _displayName(String word) {
  for (final d in kMagicWords) {
    if (d.word == word) return d.displayName;
  }
  return word;
}

class FamilyMapScreen extends ConsumerWidget {
  const FamilyMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    final family = online.family;
    final me = online.me;
    if (family == null || me == null) {
      return const WordlerScaffold(title: 'The family map', body: Center(child: CircularProgressIndicator()));
    }
    void open(OnlineMember m) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlotScreen(uid: m.uid)));
    return WordlerScaffold(
      title: family.name,
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WColors.grassField,
                borderRadius: BorderRadius.circular(WSize.radiusCard),
                border: Border.all(color: WColors.ink, width: WSize.outline),
              ),
              child: LayoutBuilder(builder: (context, c) => _MapLayout(
                    size: c.biggest,
                    members: family.members,
                    meUid: me.uid,
                    onTap: open,
                  )),
            ),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyCard(
            onTap: () => open(me),
            child: Row(children: [
              PlayerAvatar(player: _asPlayer(me), size: 40),
              const SizedBox(width: WSize.gap3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Your plot: ${me.buildingCount} building${me.buildingCount == 1 ? '' : 's'}',
                    style: WText.heading.copyWith(fontSize: 20),
                  ),
                  const Text('Tap any plot to see its buildings.', style: WText.label),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// The plots in a ring around the Town Square (which comes later).
class _MapLayout extends StatelessWidget {
  const _MapLayout({required this.size, required this.members, required this.meUid, required this.onTap});

  final Size size;
  final List<OnlineMember> members;
  final String meUid;
  final void Function(OnlineMember) onTap;

  @override
  Widget build(BuildContext context) {
    final center = size.center(Offset.zero);
    final plot = (size.shortestSide * 0.27).clamp(70.0, 120.0);
    final radius = size.shortestSide / 2 - plot * 0.72;
    final n = max(members.length, 1);
    final spots = [
      for (int i = 0; i < members.length; i++)
        center + Offset.fromDirection(-3 * pi / 4 + 2 * pi * i / n, radius),
    ];
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _RoadsPainter(center, spots))),
        Positioned(
          left: center.dx - plot * 0.55,
          top: center.dy - plot * 0.55,
          width: plot * 1.1,
          height: plot * 1.1,
          child: Semantics(
            label: 'Town Square, coming later',
            child: const _Diamond(
              fill: WColors.paper,
              dashed: true,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Town Square', textAlign: TextAlign.center, style: WText.buttonSmall),
                Text('coming later', textAlign: TextAlign.center, style: WText.label),
              ]),
            ),
          ),
        ),
        for (int i = 0; i < members.length; i++)
          Positioned(
            left: spots[i].dx - plot / 2,
            top: spots[i].dy - plot / 2,
            width: plot,
            height: plot + 16,
            child: _Plot(member: members[i], isMe: members[i].uid == meUid, size: plot, onTap: () => onTap(members[i])),
          ),
      ],
    );
  }
}

class _RoadsPainter extends CustomPainter {
  _RoadsPainter(this.center, this.spots);

  final Offset center;
  final List<Offset> spots;

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = const Color(0xFFD9C9A8)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    for (final s in spots) {
      canvas.drawLine(center, s, road);
    }
  }

  @override
  bool shouldRepaint(_RoadsPainter old) => old.center != center || old.spots.length != spots.length;
}

class _Diamond extends StatelessWidget {
  const _Diamond({required this.fill, required this.child, this.dashed = false, this.thick = false});

  final Color fill;
  final Widget child;
  final bool dashed;
  final bool thick;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.rotate(
          angle: pi / 4,
          child: FractionallySizedBox(
            widthFactor: 0.72,
            heightFactor: 0.72,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dashed ? WColors.muted : WColors.ink, width: thick ? 5 : 3),
              ),
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.all(8), child: FittedBox(fit: BoxFit.scaleDown, child: child)),
      ],
    );
  }
}

class _Plot extends StatelessWidget {
  const _Plot({required this.member, required this.isMe, required this.size, required this.onTap});

  final OnlineMember member;
  final bool isMe;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final words = member.buildings.keys.take(3).toList();
    final count = member.buildingCount;
    return Semantics(
      button: true,
      label: '${member.name}${isMe ? ' (you)' : ''}: $count building${count == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: _Diamond(
                fill: const Color(0xFF9BD86A),
                thick: isMe,
                child: words.isEmpty
                    ? const Icon(Icons.spa, color: WColors.grass, size: 28)
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final w in words)
                          Image.asset(buildingSprite(w), width: size * 0.3, height: size * 0.3,
                              errorBuilder: (_, __, ___) => Icon(Icons.home, size: size * 0.25, color: WColors.ink)),
                      ]),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WColors.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                ),
                child: Text('$count', style: WText.buttonSmall.copyWith(color: WColors.ink)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -14,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: memberColor(member),
                    borderRadius: BorderRadius.circular(WSize.radiusChip),
                    border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                  ),
                  child: Text(member.name, maxLines: 1, style: WText.buttonSmall.copyWith(color: WColors.ink, fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One member's plot: their buildings and nothing else.
class PlotScreen extends ConsumerWidget {
  const PlotScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    final m = online.family?.member(uid);
    if (m == null) {
      return const WordlerScaffold(title: 'Plot', body: SizedBox.shrink());
    }
    final isMe = uid == online.account?.uid;
    final today = dailyDateKey(DateTime.now());
    final fresh = m.newOnDay(today);
    final count = m.buildingCount;
    return WordlerScaffold(
      title: isMe ? 'Your plot' : "${m.name}'s plot",
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          ChunkyCard(
            child: Row(children: [
              PlayerAvatar(player: _asPlayer(m), size: 48),
              const SizedBox(width: WSize.gap3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.name, style: WText.heading.copyWith(fontSize: 20)),
                  Text(
                    '$count building${count == 1 ? '' : 's'}${m.playedOn(today) ? ' · played today' : ''}',
                    style: WText.label.copyWith(fontSize: 15),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: WSize.gap3),
          if (m.buildings.isEmpty)
            ChunkyCard(
              child: Text(
                isMe ? 'No buildings yet. Spell a magic word in your village to raise one.' : 'No buildings yet.',
                style: WText.body,
              ),
            )
          else
            ChunkyCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(children: [
                for (final e in m.buildings.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Image.asset(buildingSprite(e.key), width: 44, height: 44,
                          errorBuilder: (_, __, ___) => const Icon(Icons.home, size: 36, color: WColors.ink)),
                      const SizedBox(width: WSize.gap3),
                      Expanded(child: Text(_displayName(e.key), style: WText.heading.copyWith(fontSize: 20))),
                      if (e.value > 1) Text('x${e.value}', style: WText.bodyBold),
                      if (fresh.contains(e.key)) ...[
                        const SizedBox(width: WSize.gap2),
                        const _Pill('new today', WColors.sun),
                      ],
                    ]),
                  ),
              ]),
            ),
          const SizedBox(height: WSize.gap3),
          Text(
            isMe
                ? 'The family sees only your buildings. Your words, letters and coins stay on this phone.'
                : "Only ${m.name}'s buildings are shared. Their words, letters and coins stay on their phone.",
            style: WText.label,
          ),
        ],
      ),
    );
  }
}
