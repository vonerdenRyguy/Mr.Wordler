import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../daily/daily_seed.dart' show dailyDateKey;
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
      );
}

class FamilyOnlineController extends StateNotifier<FamilyOnlineState> {
  FamilyOnlineController({required Future<FamilyBackend?> backend, String? prefix})
      : _prefix = prefix ?? PlayerKeys.prefix,
        super(const FamilyOnlineState()) {
    _ready = _start(backend);
  }

  static const prefsKey = 'familyOnlineData';
  final String _prefix;
  FamilyBackend? _backend;
  StreamSubscription<OnlineFamily?>? _familySub;
  StreamSubscription<RequestStatus>? _requestSub;
  late final Future<void> _ready;

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
      }),
    );
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
        state = state.copyWith(stage: OnlineStage.noFamily, clearFamily: true);
        _save();
        _backend?.saveProfile(clearFamily: true).catchError((Object _) {});
        return;
      }
      state = state.copyWith(stage: OnlineStage.member, familyId: familyId, family: family);
    }, onError: (Object _) {});
  }

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
    await _backend!.leave(fid);
    state = state.copyWith(stage: OnlineStage.noFamily, clearFamily: true);
    await _save();
  }

  Future<void> signOut() async {
    unawaited(_familySub?.cancel());
    unawaited(_requestSub?.cancel());
    _familySub = null;
    _requestSub = null;
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
