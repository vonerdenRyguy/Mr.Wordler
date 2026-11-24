import 'dart:math';

import 'package:flutter/material.dart';

import '../game/letter_tile.dart';
import '../game/word_runs.dart';
import '../ui/chunky_button.dart';
import '../ui/tokens.dart';
import 'discovery_journal_view.dart' show lettersTowardWord;
import 'magic_word.dart';

// The cards that open when you tap something in Village view, plus the
// "Build your first building" helper. All are plain widgets; the screen
// decides what they do.

typedef DefinitionLoader = Future<String?> Function(String word);

Future<T?> showVillageSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SheetFrame(child: child),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: WColors.card,
        border: Border(top: BorderSide(color: WColors.ink, width: WSize.outline)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(WSize.radiusHero)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(WSize.screenPadding, 12, WSize.screenPadding, WSize.screenPadding),
          child: child,
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: ChunkyIconButton(icon: Icons.close, tooltip: 'Close', onPressed: () => Navigator.of(context).pop()),
    );
  }
}

/// "WELL means ..." with loading and offline text.
class _MeaningBox extends StatelessWidget {
  const _MeaningBox({required this.word, required this.loadDefinition});

  final String word;
  final DefinitionLoader loadDefinition;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WColors.paper,
        border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$word means', style: WText.label),
          const SizedBox(height: 4),
          FutureBuilder<String?>(
            // Keyed by word so switching words in the card reloads it.
            key: ValueKey(word),
            future: loadDefinition(word),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Text('Looking it up...', style: WText.body.copyWith(color: WColors.muted));
              }
              final definition = snapshot.data;
              if (definition == null || definition.isEmpty) {
                return Text("We'll look this up next time you're online.",
                    style: WText.body.copyWith(color: WColors.muted));
              }
              return Text(definition, style: WText.body);
            },
          ),
        ],
      ),
    );
  }
}

/// What a building card's ability button does, if it has one.
class BuildingAbility {
  const BuildingAbility(this.label, this.onPressed);

  final String label;
  // Null = shown disabled.
  final VoidCallback? onPressed;
}

class BuildingCard extends StatelessWidget {
  const BuildingCard({
    super.key,
    required this.def,
    required this.cardImagePath,
    required this.loadDefinition,
    required this.onShowInWords,
    this.ability,
  });

  final MagicWordDef def;
  final String? cardImagePath;
  final DefinitionLoader loadDefinition;
  final VoidCallback onShowInWords;
  final BuildingAbility? ability;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFCFE9F7),
                border: Border.all(color: WColors.ink, width: WSize.outline),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: cardImagePath == null
                  ? Icon(def.icon, size: 48, color: WColors.ink)
                  : Image.asset(cardImagePath!, fit: BoxFit.contain, excludeFromSemantics: true),
            ),
            const SizedBox(width: WSize.gap3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(def.displayName, style: WText.heading)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: def.hasAbility ? WColors.sun : WColors.boardCell,
                      border: Border.all(color: WColors.ink, width: WSize.outlineSmall),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(def.hasAbility ? 'Ability' : 'Decor', style: WText.label.copyWith(color: WColors.ink)),
                  ),
                  const SizedBox(height: 6),
                  Text(def.description, style: WText.body),
                ],
              ),
            ),
            const _CloseButton(),
          ],
        ),
        const SizedBox(height: WSize.gap3),
        _MeaningBox(word: def.word, loadDefinition: loadDefinition),
        const SizedBox(height: WSize.gap3),
        Row(
          children: [
            Expanded(
              child: ChunkyButton(
                label: 'Show in Words',
                kind: ChunkyKind.secondary,
                expand: true,
                onPressed: onShowInWords,
              ),
            ),
            if (ability != null) ...[
              const SizedBox(width: WSize.gap3),
              Expanded(
                child: ChunkyButton(label: ability!.label, expand: true, onPressed: ability!.onPressed),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A word as small path-style tiles.
class PathWordTiles extends StatelessWidget {
  const PathWordTiles({super.key, required this.word, this.have});

  final String word;
  // For the helper: which letters you have (solid) vs. still need
  // (dashed). Null = all solid.
  final List<bool>? have;

  @override
  Widget build(BuildContext context) {
    final letters = word.split('');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (int i = 0; i < letters.length; i++)
          _PathTile(letter: letters[i], missing: have != null && !have![i]),
      ],
    );
  }
}

class _PathTile extends StatelessWidget {
  const _PathTile({required this.letter, required this.missing});

  final String letter;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      letter,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: WFonts.display,
        fontSize: 22,
        color: missing ? WColors.muted : const Color(0xFF4A3A2C),
      ),
    );
    if (missing) {
      return CustomPaint(
        foregroundPainter: _DashedRRectPainter(),
        child: SizedBox(width: 40, height: 40, child: Center(child: text)),
      );
    }
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFD9CBB0),
        border: Border.all(color: const Color(0xFF6B5A48), width: 1.5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: wLip(3, color: const Color(0xFF8F8068)),
      ),
      child: text,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WColors.muted
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) => false;
}

/// The card for an ordinary word. [runs] is every word through the tapped
/// letter, across first; with two, an "Also: X" chip switches between them.
class WordCard extends StatefulWidget {
  const WordCard({
    super.key,
    required this.runs,
    required this.loadDefinition,
    required this.onShowInWords,
    this.onWordChanged,
  });

  final List<WordRun> runs;
  final DefinitionLoader loadDefinition;
  final ValueChanged<WordRun> onShowInWords;
  final ValueChanged<WordRun>? onWordChanged;

  @override
  State<WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<WordCard> {
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    final run = widget.runs[_current];
    final other = widget.runs.length > 1 ? widget.runs[1 - _current] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Semantics(label: run.word, child: PathWordTiles(word: run.word))),
            const _CloseButton(),
          ],
        ),
        if (other != null) ...[
          const SizedBox(height: WSize.gap2),
          Align(
            alignment: Alignment.centerLeft,
            child: ChunkyButton(
              label: 'Also: ${other.word}',
              kind: ChunkyKind.secondary,
              size: ChunkySize.small,
              onPressed: () {
                setState(() => _current = 1 - _current);
                widget.onWordChanged?.call(widget.runs[_current]);
              },
            ),
          ),
        ],
        const SizedBox(height: WSize.gap3),
        _MeaningBox(word: run.word, loadDefinition: widget.loadDefinition),
        const SizedBox(height: WSize.gap2),
        Text('A path in your village. Only magic words become buildings.',
            style: WText.body.copyWith(color: WColors.muted)),
        const SizedBox(height: WSize.gap3),
        ChunkyButton(
          label: 'Show in Words',
          kind: ChunkyKind.secondary,
          expand: true,
          onPressed: () => widget.onShowInWords(run),
        ),
      ],
    );
  }
}

/// Just a word and what it means (the Journal's "What it means" link).
class MeaningCard extends StatelessWidget {
  const MeaningCard({super.key, required this.word, required this.loadDefinition});

  final String word;
  final DefinitionLoader loadDefinition;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: PathWordTiles(word: word)),
            const _CloseButton(),
          ],
        ),
        const SizedBox(height: WSize.gap3),
        _MeaningBox(word: word, loadDefinition: loadDefinition),
      ],
    );
  }
}

/// The Word of the day sheet on Home: the word as tiles, its meaning, and
/// what spelling it in the village earns.
class WordOfDayCard extends StatelessWidget {
  const WordOfDayCard({
    super.key,
    required this.word,
    required this.meaning,
    required this.claimed,
    required this.coins,
    required this.onVisit,
  });

  final String word;
  final String meaning;
  final bool claimed;
  final int coins;
  final VoidCallback onVisit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: Text('Word of the day', style: WText.heading)),
            const _CloseButton(),
          ],
        ),
        const SizedBox(height: WSize.gap2),
        Semantics(
          label: word,
          excludeSemantics: true,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final letter in word.split('')) SizedBox(width: 40, height: 40, child: LetterTile(letter: letter)),
            ],
          ),
        ),
        const SizedBox(height: WSize.gap3),
        Text(meaning, style: WText.body),
        const SizedBox(height: WSize.gap2),
        Text(
          claimed ? 'You spelled it today. +$coins coins earned.' : 'Spell it in your village today for +$coins coins.',
          style: WText.bodyBold.copyWith(fontSize: 16, color: claimed ? WColors.grass : WColors.ink),
        ),
        const SizedBox(height: WSize.gap3),
        ChunkyButton(label: 'Visit your village', expand: true, onPressed: onVisit),
      ],
    );
  }
}

class NotAWordCard extends StatelessWidget {
  /// The misspelled run this letter is in ("AQ"), if any.
  const NotAWordCard({super.key, this.run, this.offStar = false});
  final String? run;

  /// A real word that isn't on a new village's gold star.
  final bool offStar;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              if (run != null) ...[
                TextSpan(text: "$run isn't a word yet. ", style: WText.bodyBold),
                TextSpan(
                    text: 'Change a letter or move one away, and the words around it count again.',
                    style: WText.body),
              ] else if (offStar) ...[
                TextSpan(text: 'Start your first word on the gold star. ', style: WText.bodyBold),
                TextSpan(text: 'Cover the star with one of its letters and it counts.', style: WText.body),
              ] else ...[
                TextSpan(text: 'Not a word yet: ', style: WText.bodyBold),
                TextSpan(text: "this letter isn't part of a word on its own.", style: WText.body),
              ],
            ]),
          ),
        ),
        const _CloseButton(),
      ],
    );
  }
}

/// The magic word closest to being built from the letters you have (rack
/// plus board), ties broken by catalog order, and which of its letters you
/// have.
({MagicWordDef def, int have, List<bool> haveEach}) closestBuilding(List<String?> rack, List<String?> board) {
  final letters = [...rack, ...board];
  MagicWordDef best = kMagicWords.first;
  var bestHave = -1;
  for (final def in kMagicWords) {
    final have = lettersTowardWord(def.word, letters);
    if (have > bestHave) {
      best = def;
      bestHave = have;
    }
  }
  final counts = <String, int>{};
  for (final l in letters) {
    if (l != null) counts[l] = (counts[l] ?? 0) + 1;
  }
  final haveEach = <bool>[];
  for (final ch in best.word.split('')) {
    final left = counts[ch] ?? 0;
    haveEach.add(left > 0);
    if (left > 0) counts[ch] = left - 1;
  }
  return (def: best, have: bestHave, haveEach: haveEach);
}

/// "Build your first building": shown in Village view until there is one.
class FirstBuildingHelper extends StatelessWidget {
  const FirstBuildingHelper({
    super.key,
    required this.def,
    required this.have,
    required this.haveEach,
    required this.spritePath,
    required this.onGoToWords,
  });

  final MagicWordDef def;
  final int have;
  final List<bool> haveEach;
  final String? spritePath;
  final VoidCallback onGoToWords;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: WSize.lip),
      decoration: BoxDecoration(
        color: WColors.card,
        border: Border.all(color: WColors.ink, width: WSize.outline),
        borderRadius: BorderRadius.circular(WSize.radiusCard),
        boxShadow: wLip(WSize.lip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: spritePath == null
                    ? Icon(def.icon, size: 40, color: WColors.ink)
                    : Image.asset(spritePath!, fit: BoxFit.contain, excludeFromSemantics: true),
              ),
              const SizedBox(width: WSize.gap3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Build your first building', style: WText.heading.copyWith(fontSize: 21)),
                    const SizedBox(height: 4),
                    PathWordTiles(word: def.word, have: haveEach),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('You have $have of ${def.word.length} letters for ${def.word}', style: WText.bodyBold.copyWith(fontSize: 15)),
          Text('+10 coins for every new building', style: WText.label),
          const SizedBox(height: WSize.gap2),
          ChunkyButton(label: 'Go to Words', expand: true, onPressed: onGoToWords),
        ],
      ),
    );
  }
}
