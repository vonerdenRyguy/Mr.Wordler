import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../portfolio/level_info.dart';
import '../portfolio/neighborhood.dart';
import '../portfolio/portfolio_controller.dart';
import '../portfolio/property_tier.dart';

class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    final levelInfo = levelInfoForXp(portfolio.totalXp);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
        backgroundColor: Colors.deepPurple,
      ),
      backgroundColor: Colors.orangeAccent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _LevelCard(levelInfo: levelInfo, currency: portfolio.currency),
            const SizedBox(height: 16),
            const _TierGuideCard(),
            const SizedBox(height: 16),
            for (final neighborhood in kNeighborhoods) ...[
              _NeighborhoodCard(neighborhood: neighborhood),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Test controls (temporary -- these stand in for real mode '
              'rewards until Daily Estate Challenge / Time Attack / Theme '
              'Rush / Infinite Estate are wired up)',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _TestControls(),
          ],
        ),
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
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: const BorderSide(color: Colors.deepPurple, width: 2.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Level ${levelInfo.level}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                Row(
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text('$currency',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: LinearProgressIndicator(
                value: levelInfo.progress,
                minHeight: 12,
                backgroundColor: Colors.deepPurple.shade100,
                valueColor: const AlwaysStoppedAnimation(Colors.deepPurple),
              ),
            ),
            const SizedBox(height: 4),
            Text('${levelInfo.xpIntoLevel} / ${levelInfo.xpForNextLevel} XP'),
          ],
        ),
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
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: const BorderSide(color: Colors.deepPurple, width: 2.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How Properties Work',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            const SizedBox(height: 4),
            const Text(
              'Every neighborhood below has a few empty slots. Fill them all to complete '
              "the set and unlock that neighborhood's perk.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final entry in _tiers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(entry.tier.icon, color: Colors.deepPurple, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
                          children: [
                            TextSpan(
                                text: '${entry.tier.label}: ',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
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

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: neighborhood.color, width: 3.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 16, height: 16, color: neighborhood.color),
                const SizedBox(width: 8),
                Text(neighborhood.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const Spacer(),
                Text('$ownedCount / ${slots.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (isComplete) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.star, color: Colors.amber, size: 20),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (int i = 0; i < slots.length; i++) ...[
                  _PropertySlotTile(tier: slots[i], color: neighborhood.color),
                  if (i != slots.length - 1) const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // The neighborhood's perk, framed as a "feature you can unlock" --
            // grayed out with a lock until every slot above is filled.
            Container(
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: isComplete ? Colors.green.withOpacity(0.1) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: isComplete ? Colors.green : Colors.grey.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isComplete ? Icons.bolt : Icons.lock_outline,
                    color: isComplete ? Colors.green.shade700 : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isComplete ? 'Perk unlocked!' : 'Perk (locked)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isComplete ? Colors.green.shade700 : Colors.black54,
                          ),
                        ),
                        Text(
                          neighborhood.perkDescription,
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (!isComplete)
                          Text(
                            'Fill all ${slots.length} slots in ${neighborhood.name} to unlock this.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!isComplete && portfolio.currency >= PortfolioController.vacantLotCost)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      ref.read(portfolioProvider.notifier).fillEmptySlotWithCurrency(neighborhood.id),
                  child: Text('Fill a slot (${PortfolioController.vacantLotCost} coins)'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// One property slot. Owned slots show the tier icon in the neighborhood's
// color; empty slots are grayed out with a dashed outline and a lock, so
// it's visually clear they're something you can still get, not just
// missing.
class _PropertySlotTile extends StatelessWidget {
  const _PropertySlotTile({required this.tier, required this.color});

  final PropertyTier tier;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (tier.isOwned) {
      return Column(
        children: [
          Icon(tier.icon, color: color, size: 32),
          Text(tier.label, style: const TextStyle(fontSize: 10)),
        ],
      );
    }
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400, width: 1.5, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(6.0),
            color: Colors.grey.shade100,
          ),
          child: Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 18),
        ),
        Text('Empty', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}

class _TestControls extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(portfolioProvider.notifier);
    final random = Random();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton(
          onPressed: () => controller.addCurrency(10),
          child: const Text('+10 coins'),
        ),
        ElevatedButton(
          onPressed: () => controller.addXp(50),
          child: const Text('+50 XP'),
        ),
        ElevatedButton(
          onPressed: () {
            final neighborhood = kNeighborhoods[random.nextInt(kNeighborhoods.length)];
            final tier = PropertyTier
                .values[1 + random.nextInt(PropertyTier.values.length - 1)];
            controller.awardToFirstEmptySlot(neighborhood.id, tier);
          },
          child: const Text('Award random tile'),
        ),
      ],
    );
  }
}
