import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/letter_tile.dart';
import '../online/family_online_controller.dart';
import '../portfolio/portfolio_controller.dart';
import '../ui/reward_moment.dart';
import '../ui/tokens.dart';
import 'family_word.dart';
import 'players.dart';

/// Whether "Who's playing?" has been answered since the app opened (or
/// since someone tapped Switch). With two or more players the app shows
/// that screen until it has.
final playerPickedProvider = StateProvider<bool>((ref) => false);

/// The family word as a row of tiles: found letters show with a stripe in
/// the color of the player who found them, hidden ones are dashed boxes,
/// and once the word is found every tile is gold.
class FamilyWordSlots extends StatelessWidget {
  const FamilyWordSlots({
    super.key,
    required this.word,
    required this.data,
    required this.players,
    this.tileSize = 40,
    this.colorOf,
  });

  final String word;
  final FamilyWordData data;
  final PlayersState players;
  final double tileSize;

  /// The stripe color for a finder's id; by default the player on this
  /// phone with that id. The online family word passes member uids.
  final Color? Function(String id)? colorOf;

  @override
  Widget build(BuildContext context) {
    final revealed = data.revealed;
    final shown =
        data.solved ? word : [for (int i = 0; i < word.length; i++) revealed.contains(i) ? word[i] : '_'].join(' ');
    return Semantics(
      label: data.solved ? 'Family word found: $word' : 'Family word, ${word.length} letters: $shown',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < word.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SizedBox(
                  width: tileSize,
                  height: tileSize,
                  child: data.solved || revealed.contains(i)
                      ? LetterTile(
                          letter: word[i],
                          faceColor: data.solved ? WColors.sun : null,
                          stripe: (colorOf ?? (id) => players.byId(id)?.color)(data.finderOf(i) ?? ''),
                        )
                      : CustomPaint(painter: _DashedBoxPainter()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WColors.muted
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(8)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter oldDelegate) => false;
}

/// Pays the player holding the phone any family-word coins waiting for
/// them, and says so. Safe to call often: it does nothing when nothing is
/// owed, and waits for the player's Portfolio to finish loading first.
Future<void> claimFamilyCoins(WidgetRef ref, BuildContext context) async {
  final playerId = ref.read(playersProvider).currentId;
  final family = ref.read(familyWordProvider.notifier);
  final online = ref.read(familyOnlineProvider.notifier);
  final portfolio = ref.read(portfolioProvider.notifier);
  await family.ready;
  await portfolio.ready;
  // The online family's word (spec-09), for this player's own account.
  final onlineCoins = await online.claimWordCoins();
  if (!context.mounted || ref.read(playersProvider).currentId != playerId) return;
  // The provider may have been rebuilt for a new player while we waited.
  if (ref.read(portfolioProvider.notifier) != portfolio) return;
  final coins = family.claimOwed(playerId) + onlineCoins;
  if (coins == 0) return;
  portfolio.addCurrency(coins);
  await showRewardMoment(
    context,
    title: 'Family word found!',
    message: 'Your family found the hidden word together.',
    coins: coins,
  );
}
