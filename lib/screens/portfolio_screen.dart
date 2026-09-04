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

class _NeighborhoodCard extends ConsumerWidget {
  const _NeighborhoodCard({required this.neighborhood});

  final Neighborhood neighborhood;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    final slots = portfolio.neighborhoodSlots[neighborhood.id] ?? const [];
    final isComplete = portfolio.isNeighborhoodComplete(neighborhood.id);

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
                if (isComplete) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.star, color: Colors.amber, size: 20),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final tier in slots) ...[
                  Column(
                    children: [
                      Icon(tier.icon,
                          color: tier.isOwned ? neighborhood.color : Colors.grey.shade400,
                          size: 32),
                      Text(tier.label, style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isComplete ? 'Complete! Perk: ${neighborhood.perkDescription}' : neighborhood.perkDescription,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isComplete ? Colors.green.shade700 : Colors.black54,
                fontWeight: isComplete ? FontWeight.bold : FontWeight.normal,
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
