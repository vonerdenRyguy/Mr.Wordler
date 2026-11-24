import 'dart:async';
import 'dart:convert';
import 'dart:math' show max, min;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../daily/daily_seed.dart' show dailyDateKey;
import '../players/family_word.dart' show familyRevealOrder, kFamilyWordCoins, kFamilyWordEarlyCoins;
import '../players/players.dart';
import 'family_online_models.dart';
import 'firebase_family_backend.dart';
import 'helping.dart';

// Family online for the player holding the phone (spec-08): their sign-in,
// their family, and a request to join that is waiting for a grown-up.
//
// Saved per player under PlayerKeys.of('familyOnlineData'), so the screens
// can show the family straight away and remember a request across restarts.
// The server is the truth; this is only what we last knew.

enum OnlineStage {
  /// Firebase isn't set up in this build (or failed to start).
  unavailable,

  /// Still reading the save / starting the backend.
  loading,

  signedOut,

  /// Signed in, not in a family and not waiting.
  noFamily,

  /// Asked to join; waiting for a grown-up's yes.
  waiting,

  /// In a family.
  member,
}

class FamilyOnlineState {
  const FamilyOnlineState({
    this.stage = OnlineStage.loading,
    this.account,
    this.birthYear,
    this.group,
    this.familyId,
    this.family,
    this.waitingFor,
    this.declined = false,
    this.emailSentTo,
    this.day,
    this.notes = const [],
    this.square,
  });

  final OnlineStage stage;
  final OnlineAccount? account;
  final int? birthYear;
  final AgeGroup? group;
  final String? familyId;
  final OnlineFamily? family;

  /// The family a request is waiting on.
  final FamilyPreview? waitingFor;

  /// The last request was turned down (shown once, then cleared).
  final bool declined;

  /// An emailed sign-in link is on its way to this address.
  final String? emailSentTo;

  /// Today's family word online (spec-09), once it has loaded.
  final FamilyDay? day;

  /// Today's and yesterday's gifts and cheers in the family (spec-10).
  final List<FamilyNote> notes;

  /// The family's Town Square (spec-13), once it has loaded.
  final TownSquare? square;

  bool get isAdult => group == AgeGroup.adult;

  OnlineMember? get me {
    final a = account;
    return a == null ? null : family?.member(a.uid);
  }

  FamilyOnlineState copyWith({
    OnlineStage? stage,
    OnlineAccount? account,
    int? birthYear,
    AgeGroup? group,
    String? familyId,
    OnlineFamily? family,
    FamilyPreview? waitingFor,
    bool? declined,
    String? emailSentTo,
    FamilyDay? day,
    List<FamilyNote>? notes,
    TownSquare? square,
    bool clearFamily = false,
    bool clearWaiting = false,
    bool clearAccount = false,
    bool clearEmail = false,
  }) =>
      FamilyOnlineState(
        stage: stage ?? this.stage,
        account: clearAccount ? null : (account ?? this.account),
        birthYear: clearAccount ? null : (birthYear ?? this.birthYear),
        group: clearAccount ? null : (group ?? this.group),
        familyId: clearFamily ? null : (familyId ?? this.familyId),
        family: clearFamily ? null : (family ?? this.family),
        waitingFor: clearWaiting ? null : (waitingFor ?? this.waitingFor),
        declined: declined ?? this.declined,
        emailSentTo: clearEmail ? null : (emailSentTo ?? this.emailSentTo),
        day: clearFamily ? null : (day ?? this.day),
        notes: clearFamily ? const [] : (notes ?? this.notes),
        square: clearFamily ? null : (square ?? this.square),
      );
}

class FamilyOnlineController extends StateNotifier<FamilyOnlineState> {
  FamilyOnlineController({required Future<FamilyBackend?> backend, String? prefix, DateTime Function()? clock})
      : _prefix = prefix ?? PlayerKeys.prefix,
        _clock = clock ?? DateTime.now,
        super(const FamilyOnlineState()) {
    _ready = _start(backend);
  }

  static const prefsKey = 'familyOnlineData';
  final String _prefix;
  final DateTime Function() _clock;
  FamilyBackend? _backend;
  StreamSubscription<OnlineFamily?>? _familySub;
  StreamSubscription<RequestStatus>? _requestSub;
  StreamSubscription<FamilyDay>? _daySub;
  StreamSubscription<List<FamilyNote>>? _notesSub;
  StreamSubscription<TownSquare>? _squareSub;
  String? _dayKey;

  /// Gifts already added to this player's village rack (spec-10).
  List<String> _claimedGifts = const [];
  late final Future<void> _ready;

  /// Family-word days this player has collected coins for (spec-09).
  List<String> _paidDays = const [];
  Future<int>? _claiming;

  /// Buildings waiting to be sent once the family has loaded.
  Map<String, int>? _pendingBuildings;

  /// The email the link was sent to, kept until the link comes back.
  String? _pendingEmail;

  Future<void> get ready => _ready;
  FamilyBackend? get backend => _backend;

  String get _key => '$_prefix$prefsKey';

  Future<void> _start(Future<FamilyBackend?> backendFuture) async {
    FamilyBackend? backend;
    try {
      backend = await backendFuture;
    } catch (_) {
      backend = null;
    }
    if (!mounted) return;
    _backend = backend;
    if (backend == null) {
      state = const FamilyOnlineState(stage: OnlineStage.unavailable);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> saved = const {};
    try {
      final raw = prefs.getString(_key);
      if (raw != null) saved = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    if (!mounted) return;
    _pendingEmail = saved['pendingEmail'] as String?;
    _paidDays = [for (final d in (saved['paidWordDays'] as List? ?? const [])) d as String];
    _claimedGifts = [for (final d in (saved['claimedGifts'] as List? ?? const [])) d as String];
    final seen = saved['squareSeen'];
    if (seen is Map && seen['familyId'] is String && seen['count'] is int) {
      _squareSeen = (familyId: seen['familyId'] as String, count: seen['count'] as int);
    }
    final account = backend.account;
    if (account == null) {
      state = FamilyOnlineState(stage: OnlineStage.signedOut, emailSentTo: _pendingEmail);
      return;
    }
    final waiting = saved['waitingFamilyId'] as String?;
    state = FamilyOnlineState(
      stage: OnlineStage.noFamily,
      account: account,
      birthYear: saved['birthYear'] as int?,
      group: ageGroupFromName(saved['group'] as String?),
    );
    final familyId = saved['familyId'] as String?;
    if (familyId != null) {
      _watchFamily(familyId);
    } else if (waiting != null) {
      _watchRequest(FamilyPreview(
        familyId: waiting,
        name: saved['waitingFamilyName'] as String? ?? 'your family',
        adultNames: [for (final n in (saved['waitingAdultNames'] as List? ?? const [])) n as String],
      ));
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final s = state;
    await prefs.setString(
      _key,
      jsonEncode({
        if (s.birthYear != null) 'birthYear': s.birthYear,
        if (s.group != null) 'group': s.group!.name,
        if (s.familyId != null) 'familyId': s.familyId,
        if (s.waitingFor != null) ...{
          'waitingFamilyId': s.waitingFor!.familyId,
          'waitingFamilyName': s.waitingFor!.name,
          'waitingAdultNames': s.waitingFor!.adultNames,
        },
        if (_pendingEmail != null) 'pendingEmail': _pendingEmail,
        // So other players on this phone can tell this account is here.
        if (s.account != null) 'uid': s.account!.uid,
        if (_paidDays.isNotEmpty) 'paidWordDays': _paidDays,
        if (_claimedGifts.isNotEmpty) 'claimedGifts': _claimedGifts,
        if (_squareSeen != null) 'squareSeen': {'familyId': _squareSeen!.familyId, 'count': _squareSeen!.count},
      }),
    );
  }

  /// The online uid of each player on this phone who is signed in:
  /// uid -> player id. Read from each player's own save.
  static Future<Map<String, String>> localUids(List<Player> players) async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, String>{};
    for (final p in players) {
      try {
        final raw = prefs.getString('${p.prefix}$prefsKey');
        final uid = raw == null ? null : (jsonDecode(raw) as Map<String, dynamic>)['uid'] as String?;
        if (uid != null) out[uid] = p.id;
      } catch (_) {}
    }
    return out;
  }

  void _watchFamily(String familyId) {
    _requestSub?.cancel();
    _requestSub = null;
    _familySub?.cancel();
    state = state.copyWith(stage: OnlineStage.member, familyId: familyId, clearWaiting: true);
    _familySub = _backend!.watchFamily(familyId).listen((family) {
      if (!mounted) return;
      if (family == null) {
        // Removed from the family, or it was closed.
        _familySub?.cancel();
        _familySub = null;
        _stopDay();
        state = state.copyWith(stage: OnlineStage.noFamily, clearFamily: true);
        _save();
        _backend?.saveProfile(clearFamily: true).catchError((Object _) {});
        return;
      }
      final first = state.family == null || _daySub == null;
      state = state.copyWith(stage: OnlineStage.member, familyId: familyId, family: family);
      if (first) {
        watchToday();
        // The account's uid goes into the save for the other players here.
        _save();
      }
      final pending = _pendingBuildings;
      if (pending != null) {
        _pendingBuildings = null;
        syncBuildings(pending);
      }
    }, onError: (Object _) {});
  }

  // ---- The family word and map (spec-09) ----

  void _stopDay() {
    unawaited(_squareSub?.cancel());
    _squareSub = null;
    unawaited(_daySub?.cancel());
    _daySub = null;
    unawaited(_notesSub?.cancel());
    _notesSub = null;
    _dayKey = null;
  }

  /// Follows today's family word. Cheap to call often: it only starts again
  /// when the day has changed.
  void watchToday() {
    final fid = state.familyId;
    if (state.stage != OnlineStage.member || fid == null || _backend == null) return;
    final key = dailyDateKey(_clock());
    if (_dayKey == key && _daySub != null) return;
    _stopDay();
    _watchSquare(fid);
    _dayKey = key;
    state = state.copyWith(day: const FamilyDay());
    _daySub = _backend!.watchDay(fid, key).listen((day) {
      if (mounted && _dayKey == key) state = state.copyWith(day: day);
    }, onError: (Object _) {});
    // Gifts and cheers (spec-10): today's and yesterday's.
    final days = [key, _yesterdayKey(_clock())];
    _notesSub = _backend!.watchNotes(fid, days).listen((notes) {
      if (mounted && _dayKey == key) state = state.copyWith(notes: notes);
    }, onError: (Object _) {});
    unawaited(_backend!.cleanUpNotes(fid, days).catchError((Object _) {}));
  }

  // ---- The Town Square (spec-13) ----

  void _watchSquare(String familyId) {
    unawaited(_squareSub?.cancel());
    _squareSub = _backend!.watchSquare(familyId).listen((square) {
      if (mounted && state.familyId == familyId) state = state.copyWith(square: square);
    }, onError: (Object _) {});
  }

  List<String> get _memberUids => [for (final m in state.family?.members ?? const <OnlineMember>[]) m.uid];

  Future<TownSquare?> _changeSquare(TownSquare Function(TownSquare s, List<String> uids, DateTime now) change) async {
    await _ready;
    if (!_inFamily || state.family == null) return null;
    final uids = _memberUids;
    final now = _clock();
    try {
      final after = await _backend!.changeSquare(state.familyId!, (s) => change(s, uids, now));
      if (mounted) state = state.copyWith(square: after);
      return after;
    } catch (_) {
      return null; // Offline: these bricks are lost, which is fine.
    }
  }

  /// Adds [count] bricks to the Town Square, five at a time.
  Future<void> addBricks(int count) async {
    for (var left = count; left > 0; left -= kMaxBricksAtOnce) {
      final n = min(left, kMaxBricksAtOnce);
      if (await _changeSquare((s, uids, now) => addSquareBricks(s, n, memberUids: uids, now: now)) == null) return;
    }
  }

  /// How many finished Town Square buildings this player has celebrated,
  /// for the family it was counted in.
  ({String familyId, int count})? _squareSeen;

  /// Town Square buildings the family finished since this player last
  /// looked, now marked as seen (each is paid once, on each person's own
  /// phone). The first look at a square counts what's there as seen.
  Future<List<BuiltThing>> takeFinishedBuildings() async {
    await _ready;
    final square = state.square;
    final fid = state.familyId;
    if (!_inFamily || square == null || fid == null) return const [];
    final seen = _squareSeen;
    if (seen == null || seen.familyId != fid || seen.count > square.built.length) {
      _squareSeen = (familyId: fid, count: square.built.length);
      await _save();
      return const [];
    }
    if (square.built.length == seen.count) return const [];
    final fresh = square.built.sublist(seen.count);
    _squareSeen = (familyId: fid, count: square.built.length);
    await _save();
    return fresh;
  }

  /// This player's vote for what to build next.
  Future<bool> voteFor(String buildingId) async {
    final me = state.account?.uid;
    if (me == null) return false;
    final after =
        await _changeSquare((s, uids, now) => pickSquareBuilding(s, me, buildingId, memberUids: uids, now: now));
    return after != null;
  }

  /// Opens or closes the vote if it's due (a new week, or the square has
  /// never been used). Writes only when something changes.
  Future<void> settleSquareIfDue() async {
    await _ready;
    final current = state.square;
    if (!_inFamily || current == null || state.family == null) return;
    final settled = settleSquare(current, memberUids: _memberUids, now: _clock());
    if (jsonEncode(settled.toData()) == jsonEncode(current.toData())) return;
    await _changeSquare((s, uids, now) => settleSquare(s, memberUids: uids, now: now));
  }

  // ---- Helping (spec-10) ----

  String get _today => dailyDateKey(_clock());

  /// Letter gifts this player can still send today.
  int get giftsLeftToday {
    final me = state.account?.uid;
    return me == null ? 0 : giftsLeft(state.notes, me, _today);
  }

  /// Sends [letter] to [toUid]'s village rack. False when none are left
  /// today or it couldn't be sent (offline).
  Future<bool> giveLetter(String toUid, String letter) async {
    await _ready;
    if (!_inFamily || giftsLeftToday <= 0) return false;
    final note = FamilyNote(
      kind: NoteKind.gift,
      from: state.account!.uid,
      to: toUid,
      day: _today,
      letter: letter.toUpperCase(),
      at: _clock().millisecondsSinceEpoch,
    );
    try {
      final sent = await _backend!.sendNote(state.familyId!, note);
      // Counted straight away, before the server echoes it back.
      if (mounted && !state.notes.any((n) => n.id == sent.id)) state = state.copyWith(notes: [...state.notes, sent]);
      unawaited(addBricks(kBricksHelp));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends a sticker to [toUid], optionally about a building or the
  /// family word. False if it couldn't be sent.
  Future<bool> cheer(String toUid, String stickerId, {String? about}) async {
    await _ready;
    if (!_inFamily) return false;
    try {
      await _backend!.sendNote(
        state.familyId!,
        FamilyNote(
          kind: NoteKind.cheer,
          from: state.account!.uid,
          to: toUid,
          day: _today,
          sticker: stickerId,
          about: about,
          at: _clock().millisecondsSinceEpoch,
        ),
      );
      unawaited(addBricks(kBricksHelp));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Asks the family for [letter] today; null takes the request back.
  Future<bool> askFor(String? letter) async {
    await _ready;
    if (!_inFamily) return false;
    try {
      await _backend!.setWants(state.familyId!, letter?.toUpperCase(), _today);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// This player's request that nobody has answered yet today.
  String? get myOpenRequest {
    final me = state.me;
    return me == null ? null : openRequest(me, state.notes, _today);
  }

  /// Gifts sent to this player that aren't in their rack yet.
  List<FamilyNote> get waitingGiftsForMe {
    final me = state.account?.uid;
    if (me == null || !_inFamily) return const [];
    return waitingGifts(state.notes, me, _claimedGifts.toSet());
  }

  /// Takes up to [max] waiting gifts for the village rack and remembers
  /// them, so each gift arrives once.
  Future<List<FamilyNote>> takeGifts({int max = kGiftsPerVisit}) async {
    await _ready;
    final gifts = waitingGiftsForMe.take(max).toList();
    if (gifts.isEmpty) return const [];
    final keep = {for (final n in state.notes) n.id};
    _claimedGifts = [
      for (final id in _claimedGifts) if (keep.contains(id)) id,
      for (final g in gifts) g.id,
    ];
    await _save();
    return gifts;
  }

  bool get _inFamily => state.stage == OnlineStage.member && state.familyId != null && state.account != null;

  String _yesterdayKey(DateTime now) => dailyDateKey(now.subtract(const Duration(days: 1)));

  /// This player finished today's Daily: uncover their share of [word].
  /// Returns the letter positions they found (empty if they already had,
  /// the word is found, or the server couldn't be reached).
  Future<List<int>> recordPlayed({required DateTime now, required String word}) async {
    await _ready;
    final family = state.family;
    if (!_inFamily || family == null) return const [];
    final me = state.account!.uid;
    final key = dailyDateKey(now);
    try {
      final day = await _backend!.changeDay(
        state.familyId!,
        key,
        yesterdayKey: _yesterdayKey(now),
        change: (today, yesterday) => uncoverShare(
          today,
          uid: me,
          revealOrder: familyRevealOrder(word, now),
          memberUids: [for (final m in family.members) m.uid],
          yesterday: yesterday,
        ),
      );
      if (mounted && key == _dayKey) state = state.copyWith(day: day);
      return day.found[me] ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// A guess at today's [word]. True if it was right and the family has
  /// it now. Throws if the server can't be reached.
  Future<bool> guess({required String text, required DateTime now, required String word}) async {
    await _ready;
    if (!_inFamily) return false;
    if (text.trim().toUpperCase() != word.toUpperCase()) return false;
    final me = state.account!.uid;
    final key = dailyDateKey(now);
    final day = await _backend!.changeDay(
      state.familyId!,
      key,
      yesterdayKey: _yesterdayKey(now),
      change: (today, yesterday) => solveByGuess(today, uid: me, yesterday: yesterday),
    );
    if (mounted && key == _dayKey) state = state.copyWith(day: day);
    return true;
  }

  /// Coins for family words found today or yesterday that this player
  /// hasn't collected yet (0 if none). The caller adds them to the
  /// Portfolio. Safe to call often.
  Future<int> claimWordCoins() {
    final running = _claiming;
    if (running != null) return running.then((_) => 0);
    final next = _claim().whenComplete(() => _claiming = null);
    _claiming = next;
    return next;
  }

  Future<int> _claim() async {
    await _ready;
    if (!mounted || !_inFamily) return 0;
    final now = _clock();
    var coins = 0;
    final paid = [..._paidDays];
    for (final key in [dailyDateKey(now), _yesterdayKey(now)]) {
      if (paid.contains(key)) continue;
      FamilyDay day;
      final live = state.day;
      if (key == _dayKey && live != null && live.solved) {
        day = live;
      } else {
        try {
          day = await _backend!.getDay(state.familyId!, key);
        } catch (_) {
          continue;
        }
      }
      if (!day.solved) continue;
      coins += day.solvedEarly ? kFamilyWordEarlyCoins : kFamilyWordCoins;
      paid.add(key);
    }
    if (coins == 0 || !mounted) return 0;
    final newlyPaid = paid.length - _paidDays.length;
    _paidDays = paid.length > 4 ? paid.sublist(paid.length - 4) : paid;
    await _save();
    // Each person's share of the family word's bricks (spec-13).
    for (int i = 0; i < newlyPaid; i++) {
      unawaited(addBricks(kBricksFamilyWord));
    }
    return coins;
  }

  /// Shares this player's buildings (magic word -> count) with the family.
  /// Buildings that went up since the last time count as new today. Does
  /// nothing outside a family, or when nothing changed.
  Future<void> syncBuildings(Map<String, int> buildings) async {
    await _ready;
    if (!_inFamily) return;
    final me = state.me;
    if (me == null) {
      _pendingBuildings = buildings;
      return;
    }
    // Sent once even when empty, so a brand new village's first building
    // counts as new rather than as "already there".
    if (_sameCounts(me.buildings, buildings) && me.newOn != null) return;
    final key = dailyDateKey(_clock());
    // The very first time, nothing counts as new: it was all there before.
    final firstTime = me.newOn == null && me.buildings.isEmpty;
    final newly = firstTime
        ? const <String>[]
        : [for (final e in buildings.entries) if (e.value > (me.buildings[e.key] ?? 0)) e.key];
    final newList = {...me.newOnDay(key), ...newly}.where(buildings.containsKey).toList();
    try {
      await _backend!.updateBuildings(state.familyId!, buildings: buildings, newBuildings: newList, newOn: key);
      final added = firstTime
          ? 0
          : buildings.entries.fold<int>(0, (n, e) => n + max(0, e.value - (me.buildings[e.key] ?? 0)));
      if (added > 0) unawaited(addBricks(kBricksNewBuilding * added));
    } catch (_) {
      // Offline: sent next time.
    }
  }

  static bool _sameCounts(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  void _watchRequest(FamilyPreview family) {
    _requestSub?.cancel();
    state = state.copyWith(stage: OnlineStage.waiting, waitingFor: family, declined: false);
    _requestSub = _backend!.watchRequest(family.familyId).listen((status) async {
      if (!mounted) return;
      switch (status) {
        case RequestStatus.waiting:
          break;
        case RequestStatus.accepted:
          await _backend!.saveProfile(familyId: family.familyId);
          _watchFamily(family.familyId);
          await _save();
        case RequestStatus.declined:
          _requestSub?.cancel();
          _requestSub = null;
          state = state.copyWith(stage: OnlineStage.noFamily, declined: true, clearWaiting: true);
          await _save();
      }
    }, onError: (Object _) {});
  }

  Future<void> _signedIn(OnlineAccount account, int birthYear, AgeGroup group) async {
    _pendingEmail = null;
    state = state.copyWith(
      stage: OnlineStage.noFamily,
      account: account,
      birthYear: birthYear,
      group: group,
      clearEmail: true,
    );
    await _backend!.saveProfile(birthYear: birthYear, group: group);
    // Signing back in: pick up the family this account is already in.
    String? familyId;
    try {
      familyId = await _backend!.savedFamilyId();
    } catch (_) {}
    if (familyId != null && mounted) _watchFamily(familyId);
    await _save();
  }

  /// Grown-ups and teens. False if they backed out of Google's sheet.
  Future<bool> signInWithGoogle({required int birthYear, required AgeGroup group}) async {
    final account = await _backend!.signInWithGoogle();
    if (account == null) return false;
    await _signedIn(account, birthYear, group);
    return true;
  }

  Future<void> sendEmailLink(String email, {required int birthYear, required AgeGroup group}) async {
    await _backend!.sendEmailLink(email);
    _pendingEmail = email;
    state = state.copyWith(emailSentTo: email, birthYear: birthYear, group: group);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({'pendingEmail': email, 'birthYear': birthYear, 'group': group.name}),
    );
  }

  /// Called with every link the app is opened with. True if it signed in.
  Future<bool> handleLink(String link) async {
    await _ready;
    final backend = _backend;
    final email = _pendingEmail;
    if (backend == null || email == null || !backend.isEmailLink(link)) return false;
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> saved = const {};
    try {
      saved = jsonDecode(prefs.getString(_key) ?? '{}') as Map<String, dynamic>;
    } catch (_) {}
    final account = await backend.finishEmailLink(email: email, link: link);
    await _signedIn(
      account,
      saved['birthYear'] as int? ?? state.birthYear ?? 1970,
      ageGroupFromName(saved['group'] as String?) ?? state.group ?? AgeGroup.adult,
    );
    return true;
  }

  /// Children under 13: no email, no Google.
  Future<void> signInAsChild({required int birthYear}) async {
    final account = await _backend!.signInAsChild();
    await _signedIn(account, birthYear, AgeGroup.child);
  }

  Future<void> createFamily({required String name, required MemberInfo me}) async {
    final family = await _backend!.createFamily(name: name, me: me);
    state = state.copyWith(family: family);
    _watchFamily(family.id);
    await _save();
  }

  Future<FamilyPreview?> findFamily(String code) => _backend!.findFamily(code);

  Future<void> requestToJoin({required FamilyPreview family, required String code, required MemberInfo me}) async {
    await _backend!.requestToJoin(
      family: family,
      code: code,
      me: me,
      birthYear: state.birthYear ?? 0,
      group: state.group ?? AgeGroup.child,
    );
    _watchRequest(family);
    await _save();
  }

  Future<void> cancelRequest() async {
    final waiting = state.waitingFor;
    if (waiting == null) return;
    await _backend!.cancelRequest(waiting.familyId);
    _requestSub?.cancel();
    _requestSub = null;
    state = state.copyWith(stage: OnlineStage.noFamily, clearWaiting: true);
    await _save();
  }

  void clearDeclined() => state = state.copyWith(declined: false);

  Future<void> approve(JoinRequest request) => _backend!.approve(state.familyId!, request);
  Future<void> decline(JoinRequest request) => _backend!.decline(state.familyId!, request);
  Future<String> newCode() => _backend!.newCode(state.familyId!);
  Future<void> renameFamily(String name) => _backend!.renameFamily(state.familyId!, name);
  Future<void> removeMember(String uid) => _backend!.removeMember(state.familyId!, uid);

  /// Keeps the family's copy of this player's name, color and level up to
  /// date with the phone's.
  Future<void> syncMe(MemberInfo info) async {
    final me = state.me;
    final fid = state.familyId;
    if (me == null || fid == null) return;
    if (me.name == info.name && me.colorIndex == info.colorIndex && me.level == info.level) return;
    try {
      await _backend!.updateMe(fid, info);
    } catch (_) {
      // Offline: try again next time.
    }
  }

  /// A finished Daily: the family sees this player has played today.
  Future<void> markPlayed(DateTime now) async {
    await _ready;
    final fid = state.familyId;
    if (state.stage != OnlineStage.member || fid == null) return;
    final firstToday = state.me?.playedDay != dailyDateKey(now);
    try {
      await _backend!.setPlayedDay(fid, dailyDateKey(now));
      if (firstToday) unawaited(addBricks(kBricksDaily));
    } catch (_) {
      // Offline: the family just won't see it today.
    }
  }

  Future<void> leave() async {
    final fid = state.familyId;
    if (fid == null) return;
    unawaited(_familySub?.cancel());
    _familySub = null;
    _stopDay();
    await _backend!.leave(fid);
    state = state.copyWith(stage: OnlineStage.noFamily, clearFamily: true);
    await _save();
  }

  Future<void> signOut() async {
    unawaited(_familySub?.cancel());
    unawaited(_requestSub?.cancel());
    _familySub = null;
    _requestSub = null;
    _stopDay();
    await _backend!.signOut();
    _pendingEmail = null;
    state = const FamilyOnlineState(stage: OnlineStage.signedOut);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> deleteAccount() async {
    // If this throws (a fresh sign-in is needed), nothing has changed yet.
    await _backend!.deleteAccount(state.familyId ?? state.waitingFor?.familyId);
    unawaited(_familySub?.cancel());
    unawaited(_requestSub?.cancel());
    _familySub = null;
    _requestSub = null;
    _stopDay();
    await _backend!.signOut();
    _pendingEmail = null;
    state = const FamilyOnlineState(stage: OnlineStage.signedOut);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  @override
  void dispose() {
    _familySub?.cancel();
    _requestSub?.cancel();
    _daySub?.cancel();
    _notesSub?.cancel();
    _squareSub?.cancel();
    super.dispose();
  }
}

/// Makes the backend for a player. Overridden in tests with fakes.
final familyBackendFactoryProvider = Provider<Future<FamilyBackend?> Function(String playerId)>(
  (ref) => (playerId) async => firebaseReady ? await FirebaseFamilyBackend.forPlayer(playerId) : null,
);

final familyOnlineProvider = StateNotifierProvider<FamilyOnlineController, FamilyOnlineState>((ref) {
  final playerId = ref.watch(currentPlayerIdProvider);
  final factory = ref.watch(familyBackendFactoryProvider);
  return FamilyOnlineController(backend: factory(playerId));
});
