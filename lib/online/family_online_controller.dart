import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../daily/daily_seed.dart' show dailyDateKey;
import '../players/family_word.dart' show familyRevealOrder, kFamilyWordCoins, kFamilyWordEarlyCoins;
import '../players/players.dart';
import 'family_online_models.dart';
import 'firebase_family_backend.dart';

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
  String? _dayKey;
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
    unawaited(_daySub?.cancel());
    _daySub = null;
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
    _dayKey = key;
    state = state.copyWith(day: const FamilyDay());
    _daySub = _backend!.watchDay(fid, key).listen((day) {
      if (mounted && _dayKey == key) state = state.copyWith(day: day);
    }, onError: (Object _) {});
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
    if (!_inFamily) return 0;
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
    _paidDays = paid.length > 4 ? paid.sublist(paid.length - 4) : paid;
    await _save();
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
    if (_sameCounts(me.buildings, buildings)) return;
    final key = dailyDateKey(_clock());
    // The very first time, nothing counts as new: it was all there before.
    final firstTime = me.newOn == null && me.buildings.isEmpty;
    final newly = firstTime
        ? const <String>[]
        : [for (final e in buildings.entries) if (e.value > (me.buildings[e.key] ?? 0)) e.key];
    final newList = {...me.newOnDay(key), ...newly}.where(buildings.containsKey).toList();
    try {
      await _backend!.updateBuildings(state.familyId!, buildings: buildings, newBuildings: newList, newOn: key);
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
    try {
      await _backend!.setPlayedDay(fid, dailyDateKey(now));
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
