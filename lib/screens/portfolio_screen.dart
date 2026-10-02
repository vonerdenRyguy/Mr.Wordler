import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../portfolio/level_info.dart';
import '../portfolio/neighborhood.dart';
import '../portfolio/portfolio_controller.dart';
import '../portfolio/property_tier.dart';
import '../ui/chunky_button.dart';
import '../ui/chunky_card.dart';
import '../ui/tokens.dart';
import '../ui/wordler_scaffold.dart';

class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    final levelInfo = levelInfoForXp(portfolio.totalXp);

    return WordlerScaffold(
      title: 'Portfolio',
      body: ListView(
        padding: const EdgeInsets.all(WSize.screenPadding),
        children: [
          _LevelCard(levelInfo: levelInfo, currency: portfolio.currency),
          const SizedBox(height: WSize.gap3),
          const _TierGuideCard(),
          const SizedBox(height: WSize.gap3),
          for (final neighborhood in kNeighborhoods) ...[
            _NeighborhoodCard(neighborhood: neighborhood),
            const SizedBox(height: WSize.gap3),
          ],
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.levelInfo, required this.currency});

  final LevelInfo levelInfo;
  final int currency;

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      hero: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Level ${levelInfo.level}', style: WText.heading)),
              Container(
                padding: const EdgeInsets.only(left: 4, right: 12),
                height: 36,
                decoration: BoxDecoration(
                  color: WColors.card,
                  border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                  borderRadius: BorderRadius.circular(WSize.radiusChip),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.monetization_on, color: WColors.sun, size: 28),
                    const SizedBox(width: 4),
                    Text('$currency', style: WText.button),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: WSize.gap2),
          ClipRRect(
            borderRadius: BorderRadius.circular(6.0),
            child: LinearProgressIndicator(
              value: levelInfo.progress,
              minHeight: 12,
              color: WColors.grass,
              backgroundColor: WColors.boardCell,
            ),
          ),
          const SizedBox(height: WSize.gap1),
          Text('${levelInfo.xpIntoLevel} / ${levelInfo.xpForNextLevel} XP', style: WText.label),
        ],
      ),
    );
  }
}

// Explains the property tier ladder and how each tier is actually earned,
// so a grayed-out slot elsewhere on the screen means something concrete
// instead of just looking locked.
class _TierGuideCard extends StatelessWidget {
  const _TierGuideCard();

  static const _tiers = [
    (
      tier: PropertyTier.vacantLot,
      how: 'Complete the Daily Estate Challenge (any time), or spend coins earned from '
          'Time Attack / Theme Rush / Infinite Estate to fill an empty slot directly.',
    ),
    (
      tier: PropertyTier.cottage,
      how: 'Complete the Daily Estate Challenge in under 6 minutes.',
    ),
    (
      tier: PropertyTier.house,
      how: 'Complete the Daily Estate Challenge in under 3 minutes, or find the hidden '
          'bonus word.',
    ),
    (
      tier: PropertyTier.mansion,
      how: 'Complete the Daily Estate Challenge quickly (under 6 minutes) AND find the '
          'hidden bonus word in the same run.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ChunkyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How Properties Work', style: WText.heading.copyWith(fontSize: 22)),
          const SizedBox(height: WSize.gap1),
          const Text(
            'Every neighborhood below has a few empty slots. Fill them all to complete '
            "the set and unlock that neighborhood's perk.",
            style: WText.body,
          ),
          const SizedBox(height: WSize.gap3),
          for (final entry in _tiers)
            Padding(
              padding: const EdgeInsets.only(bottom: WSize.gap2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(entry.tier.icon, color: WColors.ink, size: 24),
                  const SizedBox(width: WSize.gap2),
                  Expanded(
                    child: RichText(
                      textScaler: MediaQuery.textScalerOf(context),
                      text: TextSpan(
                        style: WText.body.copyWith(fontSize: 15),
                        children: [
                          TextSpan(text: '${entry.tier.label}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: entry.how),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NeighborhoodCard extends ConsumerWidget {
  const _NeighborhoodCard({required this.neighborhood});

  final Neighborhood neighborhood;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    final slots = portfolio.neighborhoodSlots[neighborhood.id] ?? const [];
    final isComplete = portfolio.isNeighborhoodComplete(neighborhood.id);
    final ownedCount = slots.where((t) => t.isOwned).length;

    return ChunkyCard(
      stripe: neighborhood.color,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(neighborhood.name, style: WText.heading.copyWith(fontSize: 22))),
              Text('$ownedCount / ${slots.length}', style: WText.label),
              if (isComplete) ...[
                const SizedBox(width: 6),
                const Icon(Icons.star, color: WColors.sun, size: 22),
              ],
            ],
          ),
          const SizedBox(height: WSize.gap2),
          Row(
            children: [
              for (int i = 0; i < slots.length; i++) ...[
                _PropertySlotTile(tier: slots[i], color: neighborhood.color),
                if (i != slots.length - 1) const SizedBox(width: WSize.gap3),
              ],
            ],
          ),
          const SizedBox(height: WSize.gap3),
          // The neighborhood's perk, framed as a "feature you can unlock" --
          // grayed out with a lock until every slot above is filled.
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: isComplete ? WColors.leafTint : WColors.paper,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: isComplete ? WColors.grass : WColors.muted, width: WSize.outlineSmall),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isComplete ? Icons.bolt : Icons.lock_outline,
                  color: isComplete ? WColors.grass : WColors.muted,
                  size: 22,
                ),
                const SizedBox(width: WSize.gap2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isComplete ? 'Perk unlocked!' : 'Perk (locked)',
                        style: WText.label.copyWith(color: isComplete ? WColors.grass : WColors.muted),
                      ),
                      Text(neighborhood.perkDescription, style: WText.body.copyWith(fontSize: 15)),
                      if (!isComplete)
                        Text(
                          'Fill all ${slots.length} slots in ${neighborhood.name} to unlock this.',
                          style: WText.label.copyWith(fontWeight: FontWeight.w400),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isComplete && portfolio.currency >= PortfolioController.vacantLotCost) ...[
            const SizedBox(height: WSize.gap2),
            Align(
              alignment: Alignment.centerRight,
              child: ChunkyButton(
                label: 'Fill a slot (${PortfolioController.vacantLotCost} coins)',
                kind: ChunkyKind.secondary,
                size: ChunkySize.small,
                onPressed: () => ref.read(portfolioProvider.notifier).fillEmptySlotWithCurrency(neighborhood.id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// One property slot. Owned slots show the tier icon in the neighborhood's
// color; empty slots are grayed out with a lock, so it's visually clear
// they're something you can still get, not just missing.
class _PropertySlotTile extends StatelessWidget {
  const _PropertySlotTile({required this.tier, required this.color});

  final PropertyTier tier;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (tier.isOwned) {
      return Column(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(tier.icon, color: WColors.ink, size: 26),
          ),
          Text(tier.label, style: WText.label.copyWith(color: WColors.ink)),
        ],
      );
    }
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: WColors.muted, width: 1.5),
            borderRadius: BorderRadius.circular(10),
            color: WColors.paper,
          ),
          child: const Icon(Icons.lock_outline, color: WColors.muted, size: 20),
        ),
        const Text('Empty', style: WText.label),
      ],
    );
  }
}
