import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../online/family_online_controller.dart';
import '../online/family_online_models.dart';
import '../players/player_summary.dart';
import '../portfolio/portfolio_controller.dart';
import '../sound/sound_service.dart' show Sfx;
import '../ui/reward_moment.dart';
import '../players/players.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/min_height_box.dart';
import '../ui/tokens.dart';
import '../ui/wordler_scaffold.dart';
import 'family_word_online_screens.dart' show PlotScreen, buildingSprite, memberColor;
import 'square_art.dart';

// The Town Square (spec-13): an online family's Family page is their little
// world. Everyone's plot sits around the square; in the middle stands what
// the family is building, brick by brick, or a vote sign when it's time to
// pick the next thing. Bricks come from playing as usual.

Player _asPlayer(OnlineMember m) => Player(id: m.uid, name: m.name, colorIndex: m.colorIndex);

/// The Family page for an online family.
class TownSquarePage extends ConsumerStatefulWidget {
  const TownSquarePage({
    super.key,
    required this.streak,
    required this.familyWordAlert,
    required this.helpCount,
    required this.onFamilyWord,
    required this.onFromFamily,
  });

  final int streak;

  /// A red ! on the family word: you haven't played today and it isn't found.
  final bool familyWordAlert;

  /// New gifts, cheers and requests (the gift button's red number).
  final int helpCount;
  final VoidCallback onFamilyWord;
  final VoidCallback onFromFamily;

  @override
  ConsumerState<TownSquarePage> createState() => _TownSquarePageState();
}

class _TownSquarePageState extends ConsumerState<TownSquarePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(familyOnlineProvider.notifier).settleSquareIfDue();
    });
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    // Opens the vote when the square first loads, and closes it once a new
    // week starts.
    ref.listen(familyOnlineProvider.select((s) => s.square), (_, next) {
      if (next != null) ref.read(familyOnlineProvider.notifier).settleSquareIfDue();
    });
    final online = ref.watch(familyOnlineProvider);
    final family = online.family;
    final me = online.me;
    final square = online.square ?? const TownSquare();
    if (family == null || me == null) return const SizedBox.shrink();
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFBFE5F8), Color(0xFFA5D877), Color(0xFF8ACD52)],
              stops: [0, 0.22, 1],
            ),
          ),
        ),
        CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(WSize.screenPadding, pad.top + 6, WSize.screenPadding, pad.bottom + 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _FamilyHeader(
                      name: family.name,
                      streak: widget.streak,
                      alert: widget.familyWordAlert,
                      onFamilyWord: widget.onFamilyWord,
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) => MinHeightBox(
                          height: 200,
                          child: _SquareWorld(
                            family: family,
                            meUid: me.uid,
                            square: square,
                            onPlot: (m) => _open(PlotScreen(uid: m.uid)),
                            onMiddle: () =>
                                _open(square.voting ? const SquareVoteScreen() : const SquareBricksScreen()),
                          ),
                        ),
                      ),
                    ),
                    _SquareCard(
                      square: square,
                      family: family,
                      meUid: me.uid,
                      helpCount: widget.helpCount,
                      onVote: () => _open(const SquareVoteScreen()),
                      onBricks: () => _open(const SquareBricksScreen()),
                      onFromFamily: widget.onFromFamily,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The family's name and streak, with the family word as a round button.
class _FamilyHeader extends StatelessWidget {
  const _FamilyHeader({required this.name, required this.streak, required this.alert, required this.onFamilyWord});

  final String name;
  final int streak;
  final bool alert;
  final VoidCallback onFamilyWord;

  @override
  Widget build(BuildContext context) {
    return _Float(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Semantics(
              header: true,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(name, maxLines: 1, style: WText.heading.copyWith(fontSize: 23)),
              ),
            ),
            if (streak >= 2)
              Row(children: [
                const Icon(Icons.local_fire_department, color: WColors.brick, size: 18),
                Flexible(
                    child: Text('$streak days in a row', maxLines: 1, style: WText.label.copyWith(color: WColors.ink))),
              ]),
          ]),
        ),
        const SizedBox(width: WSize.gap2),
        _PillButton(
          label: 'Family word',
          icon: Icons.key,
          alert: alert ? '!' : null,
          semantics: 'Family word${alert ? '. Not played yet today' : ''}',
          onTap: onFamilyWord,
        ),
      ]),
    );
  }
}

/// A floating box on the world.
class _Float extends StatelessWidget {
  const _Float({required this.child, this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: WSize.lip),
      padding: padding,
      decoration: BoxDecoration(
        color: WColors.card.withOpacity(0.97),
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: BorderRadius.circular(WSize.radiusCard),
        boxShadow: wLip(WSize.lip),
      ),
      child: child,
    );
  }
}

/// A small tappable chip with an icon and an optional red badge.
class _PillButton extends StatelessWidget {
  const _PillButton(
      {required this.label, required this.icon, required this.semantics, required this.onTap, this.alert});

  final String label;
  final IconData icon;
  final String semantics;
  final VoidCallback onTap;
  final String? alert;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            constraints: const BoxConstraints(minHeight: WSize.tapTarget),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            margin: const EdgeInsets.only(bottom: WSize.lipSmall),
            decoration: BoxDecoration(
              color: WColors.sun,
              border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
              borderRadius: BorderRadius.circular(WSize.radiusChip),
              boxShadow: wLip(WSize.lipSmall),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: WColors.ink),
              const SizedBox(width: 4),
              Text(label, maxLines: 1, style: WText.buttonSmall.copyWith(color: WColors.ink)),
            ]),
          ),
          if (alert != null) Positioned(right: -6, top: -8, child: _RedDot(text: alert!)),
        ]),
      ),
    );
  }
}

class _RedDot extends StatelessWidget {
  const _RedDot({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WColors.brick,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WColors.white, width: 2),
      ),
      child: Text(text,
          textScaler: TextScaler.noScaling, style: WText.buttonSmall.copyWith(color: WColors.white, fontSize: 14)),
    );
  }
}

// ---- The world ------------------------------------------------------------------

class _SquareWorld extends StatelessWidget {
  const _SquareWorld({
    required this.family,
    required this.meUid,
    required this.square,
    required this.onPlot,
    required this.onMiddle,
  });

  final OnlineFamily family;
  final String meUid;
  final TownSquare square;
  final void Function(OnlineMember) onPlot;
  final VoidCallback onMiddle;

  // Where plots go, as fractions of the world: opposite corners first, so
  // two people already look balanced, then the other corners and sides.
  static const _plotSpots = [
    Offset(0.15, 0.16),
    Offset(0.85, 0.8),
    Offset(0.85, 0.16),
    Offset(0.15, 0.8),
    Offset(0.1, 0.48),
    Offset(0.9, 0.48),
  ];

  // Finished buildings, around the edge of the square.
  static const _builtSpots = [
    Offset(-0.62, -0.42),
    Offset(0.62, -0.42),
    Offset(-0.7, 0.28),
    Offset(0.7, 0.28),
    Offset(-0.25, 0.62),
    Offset(0.25, 0.62),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final plazaW = min(w * 0.7, h * 1.3);
      final plazaH = min(h * 0.5, plazaW * 0.62);
      final center = Offset(w / 2, h * 0.52);
      final plaza = Rect.fromCenter(center: center, width: plazaW, height: plazaH);
      final plotSize = (min(w, h) * 0.24).clamp(56.0, 92.0);
      final builtSize = plazaH * 0.55;
      final midSize = plazaH * 1.3;
      final building = square.building;
      final members = family.members.take(_plotSpots.length).toList();
      final built = square.built.reversed.take(_builtSpots.length).toList();

      return SizedBox(
        width: w,
        height: h,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: CustomPaint(painter: SquareGroundPainter(plaza: plaza))),
          // Trees between the plots.
          for (final t in const [Offset(0.5, 0.06), Offset(0.06, 0.62), Offset(0.94, 0.38), Offset(0.42, 0.95)])
            Positioned(
              left: t.dx * w - plotSize * 0.25,
              top: t.dy * h - plotSize * 0.4,
              child: IgnorePointer(child: SquareTree(size: plotSize * 0.5)),
            ),
          for (int i = 0; i < built.length; i++)
            Positioned(
              left: center.dx + _builtSpots[i].dx * plazaW / 2 - builtSize / 2,
              top: center.dy + _builtSpots[i].dy * plazaH / 2 - builtSize * 0.85,
              child: Semantics(
                label: '${squareBuilding(built[i].id)?.name ?? 'A building'}, built by the family',
                child: SquareBuildingArt(id: built[i].id, size: builtSize),
              ),
            ),
          // The middle: what's going up, or the vote sign.
          Positioned(
            left: center.dx - midSize / 2,
            top: center.dy - midSize * 0.78,
            width: midSize,
            height: midSize,
            child: Semantics(
              button: true,
              label: building == null
                  ? 'Town Square: time to vote for what to build'
                  : 'Town Square: ${squareBuilding(building)?.name ?? 'a building'}, '
                      '${square.progress} of ${square.goal} bricks',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMiddle,
                child: building == null
                    ? _VoteSign(size: midSize)
                    : SquareBuildingArt(
                        id: building,
                        built: square.goal == 0 ? 0 : square.progress / square.goal,
                        size: midSize,
                      ),
              ),
            ),
          ),
          for (int i = 0; i < members.length; i++)
            Positioned(
              left: _plotSpots[i].dx * w - plotSize / 2,
              top: _plotSpots[i].dy * h - plotSize / 2,
              width: plotSize,
              height: plotSize + 14,
              child: _Plot(
                member: members[i],
                isMe: members[i].uid == meUid,
                size: plotSize,
                onTap: () => onPlot(members[i]),
              ),
            ),
        ]),
      );
    });
  }
}

/// A wooden sign: "Vote!".
class _VoteSign extends StatelessWidget {
  const _VoteSign({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.1, vertical: size * 0.04),
        decoration: BoxDecoration(
          color: const Color(0xFFE3C9A0),
          border: Border.all(color: WColors.ink, width: WSize.outline),
          borderRadius: BorderRadius.circular(10),
          boxShadow: wLip(WSize.lipSmall),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.how_to_vote, size: size * 0.24, color: WColors.ink),
          Text('Vote!',
              textScaler: TextScaler.noScaling,
              style: WText.button.copyWith(color: WColors.ink, fontSize: size * 0.15)),
        ]),
      ),
      Container(width: size * 0.06, height: size * 0.18, color: WColors.wood),
      SizedBox(height: size * 0.12),
    ]);
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
    final count = member.buildingCount;
    final best = member.buildings.entries.isEmpty
        ? null
        : (member.buildings.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    return Semantics(
      button: true,
      label: '${member.name}${isMe ? ' (you)' : ''}: $count building${count == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          // Their own patch of lawn, with their biggest building on it.
          Positioned(
            top: size * 0.45,
            child: Container(
              width: size * 0.95,
              height: size * 0.4,
              decoration: BoxDecoration(
                color: const Color(0xFF7DBE4A),
                borderRadius: BorderRadius.all(Radius.elliptical(size * 0.48, size * 0.2)),
                border: isMe ? Border.all(color: WColors.sun, width: 3) : null,
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: SizedBox(
              width: size * 0.78,
              height: size * 0.78,
              child: best == null
                  ? Icon(Icons.cottage, size: size * 0.6, color: WColors.card)
                  : Image.asset(buildingSprite(best),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(Icons.cottage, size: size * 0.6, color: WColors.card)),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(2, 2, 8, 2),
              decoration: BoxDecoration(
                color: memberColor(member),
                borderRadius: BorderRadius.circular(WSize.radiusChip),
                border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                PlayerAvatar(player: _asPlayer(member), size: 22),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: size * 0.9),
                  child: Text(member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: WText.buttonSmall.copyWith(color: WColors.ink, fontSize: 14)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---- The card under the world -----------------------------------------------------

class _SquareCard extends StatelessWidget {
  const _SquareCard({
    required this.square,
    required this.family,
    required this.meUid,
    required this.helpCount,
    required this.onVote,
    required this.onBricks,
    required this.onFromFamily,
  });

  final TownSquare square;
  final OnlineFamily family;
  final String meUid;
  final int helpCount;
  final VoidCallback onVote;
  final VoidCallback onBricks;
  final VoidCallback onFromFamily;

  @override
  Widget build(BuildContext context) {
    final building = squareBuilding(square.building);
    final vote = square.vote;
    final voted = vote?.picks.length ?? 0;
    final mine = vote?.picks[meUid];
    final gift = _GiftButton(count: helpCount, onTap: onFromFamily);
    if (building == null) {
      final choices = [for (final id in vote?.choices ?? const <String>[]) squareBuilding(id)?.name ?? id];
      return _Float(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Vote for what to build', style: WText.heading.copyWith(fontSize: 22)),
          const SizedBox(height: 2),
          Text(
            mine != null
                ? 'You picked the ${squareBuilding(mine)?.name ?? mine}. $voted of ${family.members.length} voted.'
                : choices.isEmpty
                    ? 'Three ideas are on their way.'
                    : '${choices.join(', ')}?',
            style: WText.body.copyWith(fontSize: 15),
          ),
          if (square.progress > 0)
            Text('${square.progress} bricks saved up already', style: WText.label.copyWith(color: WColors.ink)),
          const SizedBox(height: WSize.gap2),
          Row(children: [
            Expanded(
              child: ChunkyButton(
                label: mine == null ? 'Vote' : 'Change my vote',
                icon: Icons.how_to_vote,
                kind: mine == null ? ChunkyKind.primary : ChunkyKind.secondary,
                onPressed: onVote,
              ),
            ),
            const SizedBox(width: WSize.gap2),
            gift,
          ]),
        ]),
      );
    }
    return _Float(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SquareBuildingArt(id: building.id, size: 46),
          const SizedBox(width: WSize.gap2),
          Expanded(
            child: Text('Building: ${building.name}', maxLines: 2, style: WText.heading.copyWith(fontSize: 22)),
          ),
        ]),
        const SizedBox(height: WSize.gap1),
        BrickBar(progress: square.progress, goal: square.goal),
        const SizedBox(height: WSize.gap2),
        Row(children: [
          Expanded(child: ChunkyButton(label: 'How to add bricks', onPressed: onBricks)),
          const SizedBox(width: WSize.gap2),
          gift,
        ]),
      ]),
    );
  }
}

/// Bricks so far toward the goal.
class BrickBar extends StatelessWidget {
  const BrickBar({super.key, required this.progress, required this.goal});

  final int progress;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final value = goal == 0 ? 0.0 : (progress / goal).clamp(0.0, 1.0);
    return Semantics(
      label: '$progress of $goal bricks',
      excludeSemantics: true,
      child: Row(children: [
        const _Brick(),
        const SizedBox(width: WSize.gap2),
        Expanded(
          child: Container(
            height: 20,
            decoration: BoxDecoration(
              color: WColors.boardCell,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value,
                  heightFactor: 1,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFFC0552F), Color(0xFFE07B4F)]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: WSize.gap2),
        Text('$progress / $goal', style: WText.button.copyWith(color: WColors.ink, fontSize: 18)),
      ]),
    );
  }
}

class _Brick extends StatelessWidget {
  const _Brick();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFFC0552F),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
      ),
    );
  }
}

/// From your family, with a red number for new things.
class _GiftButton extends StatelessWidget {
  const _GiftButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'From your family${count > 0 ? ', $count new' : ''}',
      excludeSemantics: true,
      child: Stack(clipBehavior: Clip.none, children: [
        ChunkyIconButton(icon: Icons.card_giftcard, tooltip: 'From your family', onPressed: onTap),
        if (count > 0) Positioned(right: -6, top: -8, child: _RedDot(text: count > 9 ? '9+' : '$count')),
      ]),
    );
  }
}

// ---- We built it! ----------------------------------------------------------------

bool _celebrating = false;

/// When the family has finished a Town Square building since this player
/// last looked: +15 coins each and the We built it! moment. Safe to call
/// often; does nothing outside an online family.
Future<void> celebrateSquare(WidgetRef ref, BuildContext context) async {
  if (_celebrating) return;
  _celebrating = true;
  try {
    final portfolio = ref.read(portfolioProvider.notifier);
    await portfolio.ready;
    final fresh = await ref.read(familyOnlineProvider.notifier).takeFinishedBuildings();
    if (fresh.isEmpty || !context.mounted) return;
    final coins = kSquareCoins * fresh.length;
    portfolio.addCurrency(coins);
    final family = ref.read(familyOnlineProvider).family;
    final last = squareBuilding(fresh.last.id);
    final name = last?.name ?? 'building';
    await showRewardMoment(
      context,
      title: 'We built it!',
      ribbon: 'Town Square',
      message: fresh.length == 1
          ? '${family?.name ?? 'Your family'} built a $name in the Town Square. +$kSquareCoins coins each!'
          : '${family?.name ?? 'Your family'} built ${fresh.length} buildings in the Town Square!',
      coins: coins,
      buttonLabel: 'Hooray!',
      sound: Sfx.building,
      picture: Column(mainAxisSize: MainAxisSize.min, children: [
        SquareBuildingArt(id: fresh.last.id, size: 128),
        if (family != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final m in family.members.take(6))
              Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: PlayerAvatar(player: _asPlayer(m), size: 34)),
          ]),
      ]),
    );
  } finally {
    _celebrating = false;
  }
}

// ---- This week's vote ------------------------------------------------------------

class SquareVoteScreen extends ConsumerWidget {
  const SquareVoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(familyOnlineProvider);
    final family = online.family;
    final me = online.account?.uid;
    final square = online.square;
    final vote = square?.vote;
    if (family == null || me == null || square == null) {
      return const WordlerScaffold(title: 'Family vote', body: Center(child: CircularProgressIndicator()));
    }
    if (vote == null) {
      // Everyone has voted: it's decided.
      final b = squareBuilding(square.building);
      return WordlerScaffold(
        title: 'Family vote',
        body: ListView(padding: const EdgeInsets.all(WSize.screenPadding), children: [
          if (b != null) Center(child: SquareBuildingArt(id: b.id, built: 0.3, size: 160)),
          const SizedBox(height: WSize.gap3),
          Text(b == null ? 'The vote is closed.' : "It's decided: the ${b.name}!",
              textAlign: TextAlign.center, style: WText.heading),
          const SizedBox(height: WSize.gap2),
          const Text('Now everyone adds bricks by playing.', textAlign: TextAlign.center, style: WText.body),
          const SizedBox(height: WSize.gap4),
          ChunkyButton(label: 'Done', expand: true, onPressed: () => Navigator.of(context).pop()),
        ]),
      );
    }
    final mine = vote.picks[me];
    final waiting = [
      for (final m in family.members)
        if (!vote.picks.containsKey(m.uid)) m.name
    ];
    return WordlerScaffold(
      title: 'Family vote',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          ChunkyCard(
            color: WColors.sunTint,
            child: Row(children: [
              const Icon(Icons.how_to_vote, size: 40, color: WColors.ink),
              const SizedBox(width: WSize.gap3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('What should we build next?', style: WText.heading.copyWith(fontSize: 22)),
                  const Text('Tap one. Everyone gets one vote.', style: WText.label),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: WSize.gap3),
          for (final id in vote.choices)
            Padding(
              padding: const EdgeInsets.only(bottom: WSize.gap3),
              child: _Choice(
                id: id,
                picked: mine == id,
                voters: [
                  for (final e in vote.picks.entries)
                    if (e.value == id)
                      if (family.member(e.key) case final m?) m,
                ],
                onTap: () async {
                  HapticFeedback.selectionClick();
                  final ok = await ref.read(familyOnlineProvider.notifier).voteFor(id);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text("Couldn't vote. Check the internet and try again."),
                    ));
                  }
                },
              ),
            ),
          if (waiting.isNotEmpty)
            Text(
              waiting.length == 1 ? "${waiting.single} hasn't voted yet." : 'Still to vote: ${waiting.join(', ')}.',
              textAlign: TextAlign.center,
              style: WText.body,
            ),
          const SizedBox(height: WSize.gap1),
          const Text('Voting closes when everyone has voted, or on Monday.',
              textAlign: TextAlign.center, style: WText.label),
          const SizedBox(height: WSize.gap3),
          ChunkyButton(label: 'Done', expand: true, onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.id, required this.picked, required this.voters, required this.onTap});

  final String id;
  final bool picked;
  final List<OnlineMember> voters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = squareBuilding(id);
    final name = b?.name ?? id;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: picked,
      button: true,
      label: '$name, ${voters.length} vote${voters.length == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: WSize.lip),
          decoration: BoxDecoration(
            color: picked ? const Color(0xFFFFE8A3) : WColors.card,
            border: Border.all(color: WColors.ink, width: WSize.outline),
            borderRadius: BorderRadius.circular(WSize.radiusCard),
            boxShadow: [
              if (picked) const BoxShadow(color: WColors.sun, spreadRadius: 4),
              ...wLip(WSize.lip),
            ],
          ),
          child: Row(children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [WColors.skyTint, Color(0xFF9BD46A)],
                  stops: [0.45, 0.46],
                ),
                border: Border.all(color: WColors.ink, width: WSize.outline),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SquareBuildingArt(id: id, size: 90),
            ),
            const SizedBox(width: WSize.gap3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: WText.heading.copyWith(fontSize: 24)),
                const SizedBox(height: 6),
                if (voters.isEmpty)
                  const Text('No votes yet', style: WText.label)
                else
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final m in voters) PlayerAvatar(player: _asPlayer(m), size: 30),
                  ]),
              ]),
            ),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: picked ? WColors.grass : WColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: WColors.ink, width: WSize.outline),
              ),
              child: picked ? const Icon(Icons.check, color: WColors.white, size: 20) : null,
            ),
          ]),
        ),
      ),
    );
  }
}

// ---- How to add bricks ---------------------------------------------------------------

class SquareBricksScreen extends ConsumerWidget {
  const SquareBricksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final square = ref.watch(familyOnlineProvider.select((s) => s.square)) ?? const TownSquare();
    final b = squareBuilding(square.building);
    final left = max(0, square.goal - square.progress);
    Widget earn(IconData icon, Color color, String text, String bricks) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: WColors.ink, width: WSize.outline),
              ),
              child: Icon(icon, color: WColors.ink, size: 22),
            ),
            const SizedBox(width: WSize.gap3),
            Expanded(child: Text(text, style: WText.body)),
            const SizedBox(width: WSize.gap2),
            Text(bricks, style: WText.button.copyWith(color: const Color(0xFF9A3A18), fontSize: 20)),
          ]),
        );
    return WordlerScaffold(
      title: 'Adding bricks',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          if (b != null)
            ChunkyCard(
              child: Row(children: [
                SquareBuildingArt(id: b.id, built: square.goal == 0 ? 0 : square.progress / square.goal, size: 64),
                const SizedBox(width: WSize.gap3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${b.name}: $left brick${left == 1 ? '' : 's'} to go',
                        style: WText.heading.copyWith(fontSize: 21)),
                    const SizedBox(height: 6),
                    BrickBar(progress: square.progress, goal: square.goal),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: WSize.gap3),
          ChunkyCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('EVERYONE ADDS BRICKS BY PLAYING', style: WText.label),
              const SizedBox(height: WSize.gap2),
              earn(Icons.calendar_today, WColors.skyTint, 'Play the Daily puzzle', '+$kBricksDaily'),
              earn(Icons.key, WColors.sun, 'Find the family word', '+$kBricksFamilyWord each'),
              earn(Icons.cottage, WColors.leaf, 'Raise a building in your village', '+$kBricksNewBuilding'),
              earn(Icons.card_giftcard, const Color(0xFFFFE8A3), 'Send a letter or a cheer', '+$kBricksHelp'),
            ]),
          ),
          const SizedBox(height: WSize.gap3),
          ChunkyCard(
            color: WColors.leafTint,
            child: Row(children: [
              const Icon(Icons.favorite, color: WColors.grass, size: 28),
              const SizedBox(width: WSize.gap3),
              Expanded(
                child: Text(
                  b == null
                      ? 'Bricks never go to waste: any added before the vote closes go to whatever the family picks.'
                      : "Bricks never go to waste. If the ${b.name} isn't done this week, the bricks stay and the family can finish it next week.",
                  style: WText.body,
                ),
              ),
            ]),
          ),
          const SizedBox(height: WSize.gap4),
          ChunkyButton(label: 'Got it', expand: true, onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
