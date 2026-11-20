import 'dart:math' as math;

import '../explore/island_map.dart';
import '../game/word_runs.dart';
import '../settings/word_level.dart';
import 'topic_words.dart';

// Villager wishes (spec-16). One wish at a time per villager; four kinds,
// matched to the player's word level (board N167):
//
//   topic  "an animal" / "something to eat" / "a word about weather"
//   length "a 3-letter word" / "a 4-letter word" / "a word with 6+ letters"
//   letter "a word with B" / "a word that starts with S" / "a word with Z, Q, X or J"
//   place  "a word next to me" / "a word touching the river" / "a word that reaches the forest"
//
// A wish is met by any valid word on the board, spelled anywhere in the
// village, including one that was already there.

enum WishKind { topic, length, letter, place }

class Wish {
  const Wish.topic(String this.topic)
      : kind = WishKind.topic,
        number = 0,
        flag = false,
        letters = '',
        place = null;

  /// [exactly] = exactly [number] letters; otherwise [number] or more.
  const Wish.length(this.number, {bool exactly = true})
      : kind = WishKind.length,
        flag = exactly,
        topic = null,
        letters = '',
        place = null;

  /// One of [letters] is in the word, or (with [starts]) starts it.
  const Wish.letter(this.letters, {bool starts = false})
      : kind = WishKind.letter,
        flag = starts,
        topic = null,
        number = 0,
        place = null;

  /// [place] is `near` (a letter within 2 squares of the villager's home) or
  /// a ring name (`forest`, `river`, `hills`, `mountains`).
  const Wish.place(String this.place)
      : kind = WishKind.place,
        topic = null,
        number = 0,
        flag = false,
        letters = '';

  final WishKind kind;
  final String? topic;
  final int number;

  /// length: exactly; letter: starts with.
  final bool flag;
  final String letters;
  final String? place;

  static const nearMe = 'near';

  /// What the villager says, after "wishes for".
  String describe() {
    switch (kind) {
      case WishKind.topic:
        return topicById(topic!).ask;
      case WishKind.length:
        return flag ? 'a $number-letter word' : 'a word with $number+ letters';
      case WishKind.letter:
        final list = letters.split('');
        if (flag) return 'a word that starts with ${list.first}';
        if (list.length == 1) return 'a word with ${list.first}';
        return 'a word with a ${list.sublist(0, list.length - 1).join(', ')} or ${list.last}';
      case WishKind.place:
        return switch (place) {
          nearMe => 'a word next to me',
          'river' => 'a word touching the river',
          final ring => 'a word that reaches the $ring',
        };
    }
  }

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        if (topic != null) 't': topic,
        if (kind == WishKind.length) 'n': number,
        if (kind == WishKind.length || kind == WishKind.letter) 'f': flag,
        if (kind == WishKind.letter) 'l': letters,
        if (place != null) 'p': place,
      };

  static Wish? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      switch (WishKind.values.byName(raw['k'] as String)) {
        case WishKind.topic:
          final id = raw['t'] as String;
          topicById(id);
          return Wish.topic(id);
        case WishKind.length:
          return Wish.length(raw['n'] as int, exactly: raw['f'] as bool? ?? true);
        case WishKind.letter:
          return Wish.letter(raw['l'] as String, starts: raw['f'] as bool? ?? false);
        case WishKind.place:
          return Wish.place(raw['p'] as String);
      }
    } catch (_) {
      return null; // a damaged wish is just dropped; a new one arrives
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Wish &&
      other.kind == kind &&
      other.topic == topic &&
      other.number == number &&
      other.flag == flag &&
      other.letters == letters &&
      other.place == place;

  @override
  int get hashCode => Object.hash(kind, topic, number, flag, letters, place);

  @override
  String toString() => 'Wish(${describe()})';
}

/// Whether the word [run] makes [wish] come true.
///
/// [homeCell] is where the villager moved in (for "next to me"); [ringAt]
/// maps a board cell to its ring (for place wishes).
bool wishMetBy(
  Wish wish,
  WordRun run, {
  required int homeCell,
  required Ring Function(int cell) ringAt,
  int boardWidth = 500,
}) {
  final word = run.word.toUpperCase();
  switch (wish.kind) {
    case WishKind.topic:
      return topicById(wish.topic!).hasWord(word);
    case WishKind.length:
      return wish.flag ? word.length == wish.number : word.length >= wish.number;
    case WishKind.letter:
      return wish.flag ? wish.letters.contains(word[0]) : word.split('').any(wish.letters.contains);
    case WishKind.place:
      if (wish.place == Wish.nearMe) {
        final hr = homeCell ~/ boardWidth, hc = homeCell % boardWidth;
        return run.positions.any((p) => math.max((p ~/ boardWidth - hr).abs(), (p % boardWidth - hc).abs()) <= 2);
      }
      final ring = Ring.values.byName(wish.place!);
      if (ring == Ring.river) {
        // In the river, or on the bank right next to it.
        return run.positions.any((p) {
          final r = p ~/ boardWidth, c = p % boardWidth;
          for (var dr = -1; dr <= 1; dr++) {
            for (var dc = -1; dc <= 1; dc++) {
              if (ringAt((r + dr) * boardWidth + c + dc) == Ring.river) return true;
            }
          }
          return false;
        });
      }
      return run.positions.any((p) => ringAt(p) == ring);
    }
}

// ── Choosing a new wish ──────────────────────────────────────────────────────

const _sproutLetters = ['B', 'M', 'S', 'T', 'P', 'C', 'D', 'R'];
const _startLetters = ['S', 'T', 'B', 'C', 'P', 'M', 'D', 'R', 'F', 'G', 'H', 'L'];

/// Every wish a villager could ask for at [level], given the rings the
/// player can already see ([seenRings], those with fog cleared somewhere).
List<Wish> wishesFor(WordLevel level, {Set<Ring> seenRings = const {}}) {
  final topics = [for (final t in kTopics) Wish.topic(t.id)];
  switch (level) {
    case WordLevel.sprout:
      return [
        ...topics,
        const Wish.length(3),
        const Wish.length(4),
        for (final l in _sproutLetters) Wish.letter(l),
        const Wish.place(Wish.nearMe),
      ];
    case WordLevel.explorer:
    case WordLevel.builder:
      return [
        ...topics,
        Wish.length(level == WordLevel.builder ? 5 : 4),
        for (final l in _startLetters) Wish.letter(l, starts: true),
        const Wish.place(Wish.nearMe),
        for (final r in [Ring.river, Ring.forest])
          if (seenRings.contains(r)) Wish.place(r.name),
      ];
    case WordLevel.wordsmith:
      return [
        ...topics,
        const Wish.length(6, exactly: false),
        const Wish.length(7, exactly: false),
        const Wish.letter('ZQXJ'),
        const Wish.letter('KVW'),
        const Wish.place(Wish.nearMe),
        for (final r in [Ring.forest, Ring.hills, Ring.mountains])
          if (seenRings.contains(r)) Wish.place(r.name),
      ];
  }
}

/// A new wish: one of [wishesFor], spread evenly over the four kinds, never
/// [previous], and (when it can) not one the board already satisfies
/// ([alreadyMet]) so a new wish usually gives something to do.
Wish chooseWish(
  WordLevel level,
  math.Random rng, {
  Set<Ring> seenRings = const {},
  Wish? previous,
  bool Function(Wish wish)? alreadyMet,
}) {
  final all = wishesFor(level, seenRings: seenRings);
  final byKind = <WishKind, List<Wish>>{};
  for (final w in all) {
    byKind.putIfAbsent(w.kind, () => []).add(w);
  }
  final kinds = byKind.keys.toList();
  Wish? fallback;
  for (var i = 0; i < 12; i++) {
    final kind = kinds[rng.nextInt(kinds.length)];
    final options = byKind[kind]!;
    final w = options[rng.nextInt(options.length)];
    if (w == previous) continue;
    fallback ??= w;
    if (alreadyMet != null && alreadyMet(w)) continue;
    return w;
  }
  return fallback ?? all.firstWhere((w) => w != previous, orElse: () => all.first);
}

/// An example word for [wish], from the bundled lists, or null if none fits.
/// Sprout is only shown short words. [minLetters] keeps a place wish's
/// example long enough to clear the fog there.
String? exampleWord(Wish wish, WordLevel level, math.Random rng, {int minLetters = 3}) {
  final pool = <String>{
    for (final t in kTopics) ...(level == WordLevel.sprout ? t.shortWords : t.words),
  }.toList()
    ..sort();
  Iterable<String> fits;
  switch (wish.kind) {
    case WishKind.topic:
      final t = topicById(wish.topic!);
      fits = level == WordLevel.sprout ? t.shortWords : t.words;
    case WishKind.length:
      fits = pool.where((w) => wish.flag ? w.length == wish.number : w.length >= wish.number);
    case WishKind.letter:
      fits = pool.where((w) => wish.flag ? wish.letters.contains(w[0]) : w.split('').any(wish.letters.contains));
    case WishKind.place:
      fits = pool.where((w) => w.length >= minLetters && w.length <= minLetters + 2);
  }
  final list = fits.toList();
  return list.isEmpty ? null : list[rng.nextInt(list.length)];
}
