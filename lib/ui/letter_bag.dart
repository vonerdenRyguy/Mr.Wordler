import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/grid_providers.dart';
import '../game/letter_tile.dart';
import 'pill_chip.dart';
import 'tokens.dart';

/// The letter bag chip at the end of the rack (spec-17): "+23" with a bag
/// icon. Letters that don't fit the 10-letter rack wait here, and each rack
/// letter you use brings the next one out. Tap it to see them all and swap
/// any of them into the rack. Shows nothing while the bag is empty.
class LetterBagChip extends ConsumerWidget {
  const LetterBagChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(gridGameControllerProvider.select((s) => s.bag.length));
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: PillChip(
          key: const ValueKey('letter-bag-chip'),
          icon: Icons.shopping_bag,
          value: '+$count',
          label: count == 1 ? 'letter in your bag' : 'letters in your bag',
          onTap: () => showLetterBag(context),
          tooltip: 'Letter bag',
        ),
      ),
    );
  }
}

Future<void> showLetterBag(BuildContext context) {
  // The sheet lives above the village's own provider scope, so hand it the
  // village's container.
  final container = ProviderScope.containerOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UncontrolledProviderScope(container: container, child: const _LetterBagSheet()),
  );
}

class _LetterBagSheet extends ConsumerStatefulWidget {
  const _LetterBagSheet();

  @override
  ConsumerState<_LetterBagSheet> createState() => _LetterBagSheetState();
}

class _LetterBagSheetState extends ConsumerState<_LetterBagSheet> {
  int? _picked; // index in the bag

  @override
  Widget build(BuildContext context) {
    final grid = ref.watch(gridGameControllerProvider);
    final bag = grid.bag;
    final rackSize = grid.config.rackSize;
    final rack = grid.rackCells;
    final picked = _picked != null && _picked! < bag.length ? _picked : null;

    Widget tile(String letter, {required bool selected, required VoidCallback onTap, Key? key}) => GestureDetector(
          key: key,
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? WColors.sun : Colors.transparent, width: 3),
            ),
            child: LetterTile(letter: letter),
          ),
        );

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        decoration: BoxDecoration(
          color: WColors.card,
          border: Border.all(color: WColors.ink, width: WSize.outline),
          borderRadius: BorderRadius.circular(22),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Your letter bag', style: WText.heading, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  bag.isEmpty
                      ? 'The bag is empty.'
                      : picked == null
                          ? 'Each time you use a rack letter, the next one comes out of here. '
                              'Tap a letter to swap it into your rack.'
                          : 'Tap a rack letter to swap with. It goes into the bag.',
                  style: WText.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (int i = 0; i < bag.length; i++)
                      tile(bag[i],
                          key: ValueKey('bag-letter-$i'),
                          selected: picked == i,
                          onTap: () => setState(() => _picked = picked == i ? null : i)),
                  ],
                ),
                if (picked != null) ...[
                  const SizedBox(height: 14),
                  Text('Your rack', style: WText.label, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (int i = 0; i < rackSize && i < rack.length; i++)
                        rack[i] == null
                            ? GestureDetector(
                                key: ValueKey('bag-rack-$i'),
                                onTap: () => _swap(picked, i),
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: WColors.soilDeep,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              )
                            : tile(rack[i]!, key: ValueKey('bag-rack-$i'), selected: false, onTap: () => _swap(picked, i)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _swap(int bagIndex, int rackIndex) {
    ref.read(gridGameControllerProvider.notifier).swapBagWithRack(bagIndex, rackIndex);
    setState(() => _picked = null);
  }
}
