import '../daily/daily_seed.dart';
import '../explore/island_map.dart';
import '../game/word_runs.dart';
import 'wish.dart';

// The villagers who have moved in (spec-16), saved in the village save.
// Immutable: every change returns a new book, so the village screen can
// swap it in one setState and save it.

const kMaxHearts = 5;
const kWishCoins = 5;
const kWishXp = 10;
const kBestFriendCoins = 25;

class Villager {
  const Villager({
    required this.id,
    required this.name,
    required this.cell,
    this.hearts = 0,
    this.wish,
    this.nextWishOn,
    this.granted = 0,
    this.movedInWord = '',
    this.presentClaimed = false,
  });

  /// The island map's special tile id (`v0`..`v11`).
  final String id;
  final String name;

  /// Where they moved in (their special tile's board cell). Never changes.
  final int cell;
  final int hearts;

  /// The wish they have now; null while they wait for tomorrow's.
  final Wish? wish;

  /// The Daily-day key (`2026-11-21`) on which the next wish arrives.
  final String? nextWishOn;

  /// Wishes that have come true.
  final int granted;

  /// The word that brought them home.
  final String movedInWord;
  final bool presentClaimed;

  bool get bestFriend => hearts >= kMaxHearts;

  Villager copyWith({
    String? name,
    int? hearts,
    Object? wish = _keep,
    Object? nextWishOn = _keep,
    int? granted,
    bool? presentClaimed,
  }) =>
      Villager(
        id: id,
        name: name ?? this.name,
        cell: cell,
        hearts: hearts ?? this.hearts,
        wish: identical(wish, _keep) ? this.wish : wish as Wish?,
        nextWishOn: identical(nextWishOn, _keep) ? this.nextWishOn : nextWishOn as String?,
        granted: granted ?? this.granted,
        movedInWord: movedInWord,
        presentClaimed: presentClaimed ?? this.presentClaimed,
      );

  static const _keep = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cell': cell,
        'hearts': hearts,
        if (wish != null) 'wish': wish!.toJson(),
        if (nextWishOn != null) 'nextWishOn': nextWishOn,
        'granted': granted,
        'movedInWord': movedInWord,
        'presentClaimed': presentClaimed,
      };

  static Villager? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return Villager(
        id: raw['id'] as String,
        name: raw['name'] as String,
        cell: raw['cell'] as int,
        hearts: ((raw['hearts'] as int?) ?? 0).clamp(0, kMaxHearts),
        wish: Wish.fromJson(raw['wish']),
        nextWishOn: raw['nextWishOn'] as String?,
        granted: raw['granted'] as int? ?? 0,
        movedInWord: raw['movedInWord'] as String? ?? '',
        presentClaimed: raw['presentClaimed'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A wish that just came true, for the reward moment.
class WishGranted {
  const WishGranted({
    required this.villager,
    required this.wish,
    required this.word,
    required this.becameBestFriend,
  });

  /// The villager as they are now (hearts already added).
  final Villager villager;
  final Wish wish;
  final String word;
  final bool becameBestFriend;

  int get coins => kWishCoins + (becameBestFriend ? kBestFriendCoins : 0);
  int get xp => kWishXp;
}

class VillagerBook {
  const VillagerBook([this.villagers = const []]);

  final List<Villager> villagers;

  bool get isEmpty => villagers.isEmpty;
  int get count => villagers.length;

  Villager? byId(String id) {
    for (final v in villagers) {
      if (v.id == id) return v;
    }
    return null;
  }

  bool isMet(String id) => byId(id) != null;

  Set<String> get names => {for (final v in villagers) v.name};

  VillagerBook _replace(Villager v) =>
      VillagerBook([for (final o in villagers) o.id == v.id ? v : o]);

  /// [villager] moves in (once; a second call for the same id changes nothing).
  VillagerBook moveIn(Villager villager) => isMet(villager.id) ? this : VillagerBook([...villagers, villager]);

  VillagerBook rename(String id, String name) {
    final v = byId(id);
    return v == null ? this : _replace(v.copyWith(name: name));
  }

  /// Swaps [id]'s wish for [wish]: free, any time, as often as wanted, but
  /// only while they have one (after a wish comes true the next waits for
  /// tomorrow).
  VillagerBook swapWish(String id, Wish wish) {
    final v = byId(id);
    return v == null || v.wish == null ? this : _replace(v.copyWith(wish: wish));
  }

  /// Gives [wish] to [id] straight away (their first wish at move-in).
  VillagerBook giveWish(String id, Wish wish) {
    final v = byId(id);
    return v == null ? this : _replace(v.copyWith(wish: wish, nextWishOn: null));
  }

  /// Marks every villager's wish that [runs] make true, once each.
  ({VillagerBook book, List<WishGranted> granted}) checkWishes(
    List<WordRun> runs, {
    required DateTime now,
    required Ring Function(int cell) ringAt,
    int boardWidth = 500,
  }) {
    var book = this;
    final granted = <WishGranted>[];
    final tomorrow = dailyDateKey(now.add(const Duration(days: 1)));
    for (final v in villagers) {
      final wish = v.wish;
      if (wish == null) continue;
      final hit = runs.where((r) => wishMetBy(wish, r, homeCell: v.cell, ringAt: ringAt, boardWidth: boardWidth));
      if (hit.isEmpty) continue;
      final hearts = (v.hearts + 1).clamp(0, kMaxHearts);
      final becameBestFriend = hearts >= kMaxHearts && !v.presentClaimed;
      final updated = v.copyWith(
        hearts: hearts,
        wish: null,
        nextWishOn: tomorrow,
        granted: v.granted + 1,
        presentClaimed: v.presentClaimed || becameBestFriend,
      );
      book = book._replace(updated);
      granted.add(WishGranted(villager: updated, wish: wish, word: hit.first.word, becameBestFriend: becameBestFriend));
    }
    return (book: book, granted: granted);
  }

  /// Gives a new wish to everyone whose day has come (`nextWishOn` is today
  /// or earlier). [newWish] picks one for a villager.
  VillagerBook refreshWishes(DateTime now, Wish Function(Villager v) newWish) {
    final today = dailyDateKey(now);
    var book = this;
    for (final v in villagers) {
      if (v.wish != null) continue;
      final due = v.nextWishOn;
      if (due == null || due.compareTo(today) <= 0) {
        book = book._replace(v.copyWith(wish: newWish(v), nextWishOn: null));
      }
    }
    return book;
  }

  List<dynamic> toJson() => [for (final v in villagers) v.toJson()];

  static VillagerBook fromJson(Object? raw) {
    if (raw is! List) return const VillagerBook();
    return VillagerBook([
      for (final e in raw)
        if (Villager.fromJson(e) case final v?) v,
    ]);
  }
}
