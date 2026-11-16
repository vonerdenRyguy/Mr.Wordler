import 'dart:async';
import 'dart:math';

import 'family_online_models.dart';

// An in-memory family server for tests: several FakeFamilyBackends (one
// per player or phone) share one FakeFamilyServer, so a test can play out
// "Nana starts a family, Leo asks, Nana says yes" without a network. It
// follows the same rules as firebase/firestore.rules.

class _FakeFamily {
  _FakeFamily(this.id, this.name, this.code);

  final String id;
  String name;
  String code;
  final Map<String, OnlineMember> members = {};
  final Map<String, JoinRequest> requests = {};
  final Map<String, FamilyDay> days = {};
  final Map<String, FamilyNote> notes = {};
}

class FakeFamilyServer {
  FakeFamilyServer({int seed = 1}) : _random = Random(seed);

  final Random _random;
  final Map<String, _FakeFamily> _families = {};
  final Map<String, String> _codes = {}; // code -> family id
  final Map<String, Map<String, Object?>> profiles = {};
  final Map<String, String> _uidByEmail = {}; // the same Google or email account signs back in as itself
  final _changes = StreamController<void>.broadcast();
  int _next = 1;

  /// Set to make every call fail, as if the phone were offline.
  bool offline = false;

  String newId(String kind) => '$kind${_next++}';

  void _changed() => _changes.add(null);

  void _check() {
    if (offline) throw StateError('offline');
  }

  OnlineFamily? _snapshot(String familyId, String uid) {
    final f = _families[familyId];
    if (f == null || !f.members.containsKey(uid)) return null;
    final adult = f.members[uid]!.adult;
    return OnlineFamily(
      id: f.id,
      name: f.name,
      code: f.code,
      members: f.members.values.toList(),
      requests: adult ? f.requests.values.toList() : const [],
    );
  }

  String _uniqueCode() {
    while (true) {
      final code = newFamilyCode(_random);
      if (!_codes.containsKey(code)) return code;
    }
  }

  int get familyCount => _families.length;
}

class FakeFamilyBackend implements FamilyBackend {
  FakeFamilyBackend(this.server);

  final FakeFamilyServer server;
  OnlineAccount? _account;

  /// What the Google sheet hands back next (null: the person backs out).
  String? googleEmail = 'grownup@example.com';
  String? lastEmailLinkSentTo;

  @override
  OnlineAccount? get account => _account;

  String get _uid {
    final a = _account;
    if (a == null) throw StateError('not signed in');
    return a.uid;
  }

  _FakeFamily _family(String id) {
    final f = server._families[id];
    if (f == null) throw StateError('no such family');
    return f;
  }

  bool _isAdult(_FakeFamily f) => f.members[_uid]?.adult ?? false;

  @override
  Future<OnlineAccount?> signInWithGoogle() async {
    server._check();
    final email = googleEmail;
    if (email == null) return null;
    final uid = server._uidByEmail.putIfAbsent(email, () => server.newId('u'));
    return _account = OnlineAccount(uid: uid, method: SignInMethod.google, email: email);
  }

  @override
  Future<void> sendEmailLink(String email) async {
    server._check();
    lastEmailLinkSentTo = email;
  }

  @override
  bool isEmailLink(String link) => link.startsWith('https://fake.link/');

  @override
  Future<OnlineAccount> finishEmailLink({required String email, required String link}) async {
    server._check();
    if (!isEmailLink(link)) throw ArgumentError('not a sign-in link');
    final uid = server._uidByEmail.putIfAbsent(email, () => server.newId('u'));
    return _account = OnlineAccount(uid: uid, method: SignInMethod.email, email: email);
  }

  @override
  Future<OnlineAccount> signInAsChild() async {
    server._check();
    return _account = OnlineAccount(uid: server.newId('u'), method: SignInMethod.child);
  }

  @override
  Future<void> signOut() async => _account = null;

  @override
  Future<void> saveProfile({int? birthYear, AgeGroup? group, String? familyId, bool clearFamily = false}) async {
    server._check();
    final p = server.profiles.putIfAbsent(_uid, () => {});
    if (birthYear != null) p['birthYear'] = birthYear;
    if (group != null) p['group'] = group.name;
    if (familyId != null || clearFamily) p['familyId'] = familyId;
  }

  @override
  Future<String?> savedFamilyId() async {
    server._check();
    return server.profiles[_uid]?['familyId'] as String?;
  }

  @override
  Future<OnlineFamily> createFamily({required String name, required MemberInfo me}) async {
    server._check();
    if (_account?.method == SignInMethod.child) throw StateError('children cannot start a family');
    final f = _FakeFamily(server.newId('f'), name, server._uniqueCode());
    f.members[_uid] = OnlineMember(uid: _uid, name: me.name, colorIndex: me.colorIndex, level: me.level, adult: true);
    server._families[f.id] = f;
    server._codes[f.code] = f.id;
    server.profiles.putIfAbsent(_uid, () => {})['familyId'] = f.id;
    server._changed();
    return server._snapshot(f.id, _uid)!;
  }

  @override
  Future<FamilyPreview?> findFamily(String code) async {
    server._check();
    final id = server._codes[code];
    final f = id == null ? null : server._families[id];
    if (f == null) return null;
    return FamilyPreview(
      familyId: f.id,
      name: f.name,
      adultNames: [for (final m in f.members.values) if (m.adult) m.name],
    );
  }

  @override
  Future<void> requestToJoin({
    required FamilyPreview family,
    required String code,
    required MemberInfo me,
    required int birthYear,
    required AgeGroup group,
  }) async {
    server._check();
    final f = _family(family.familyId);
    if (f.code != code) throw StateError('wrong code');
    f.requests[_uid] = JoinRequest(
      uid: _uid,
      name: me.name,
      colorIndex: me.colorIndex,
      level: me.level,
      birthYear: birthYear,
      group: group,
    );
    server._changed();
  }

  @override
  Future<void> cancelRequest(String familyId) async {
    server._check();
    server._families[familyId]?.requests.remove(_uid);
    server._changed();
  }

  RequestStatus _requestStatus(String familyId, String uid) {
    final f = server._families[familyId];
    if (f == null) return RequestStatus.declined;
    if (f.members.containsKey(uid)) return RequestStatus.accepted;
    if (f.requests.containsKey(uid)) return RequestStatus.waiting;
    return RequestStatus.declined;
  }

  // Both watchers keep the account they started with, like Firestore's
  // listeners, so a sign-out while one is open doesn't break it.
  @override
  Stream<RequestStatus> watchRequest(String familyId) async* {
    final uid = _uid;
    yield _requestStatus(familyId, uid);
    await for (final _ in server._changes.stream) {
      yield _requestStatus(familyId, uid);
    }
  }

  @override
  Stream<OnlineFamily?> watchFamily(String familyId) async* {
    final uid = _uid;
    yield server._snapshot(familyId, uid);
    await for (final _ in server._changes.stream) {
      yield server._snapshot(familyId, uid);
    }
  }

  @override
  Future<void> approve(String familyId, JoinRequest request) async {
    server._check();
    final f = _family(familyId);
    if (!_isAdult(f)) throw StateError('only grown-ups can say yes');
    if (f.requests.remove(request.uid) == null) return;
    f.members[request.uid] = OnlineMember(
      uid: request.uid,
      name: request.name,
      colorIndex: request.colorIndex,
      level: request.level,
      adult: request.group == AgeGroup.adult,
    );
    server._changed();
  }

  @override
  Future<void> decline(String familyId, JoinRequest request) async {
    server._check();
    final f = _family(familyId);
    if (!_isAdult(f)) throw StateError('only grown-ups can say no');
    f.requests.remove(request.uid);
    server._changed();
  }

  @override
  Future<void> updateMe(String familyId, MemberInfo me) async {
    server._check();
    final f = _family(familyId);
    final m = f.members[_uid];
    if (m == null) return;
    f.members[_uid] = m.copyWith(name: me.name, colorIndex: me.colorIndex, level: me.level);
    server._changed();
  }

  @override
  Future<void> setPlayedDay(String familyId, String dayKey) async {
    server._check();
    final f = _family(familyId);
    final m = f.members[_uid];
    if (m == null) return;
    f.members[_uid] = m.copyWith(playedDay: dayKey);
    server._changed();
  }

  // ---- spec-09 ----

  @override
  Stream<FamilyDay> watchDay(String familyId, String dayKey) async* {
    final uid = _uid;
    FamilyDay? read() {
      final f = server._families[familyId];
      if (f == null || !f.members.containsKey(uid)) return null;
      return f.days[dayKey] ?? const FamilyDay();
    }

    final first = read();
    if (first == null) return;
    yield first;
    await for (final _ in server._changes.stream) {
      final d = read();
      if (d == null) return;
      yield d;
    }
  }

  @override
  Future<FamilyDay> getDay(String familyId, String dayKey) async {
    server._check();
    final f = _family(familyId);
    if (!f.members.containsKey(_uid)) throw StateError('members only');
    return f.days[dayKey] ?? const FamilyDay();
  }

  @override
  Future<FamilyDay> changeDay(
    String familyId,
    String dayKey, {
    required String yesterdayKey,
    required FamilyDay Function(FamilyDay today, FamilyDay yesterday) change,
  }) async {
    server._check();
    final f = _family(familyId);
    if (!f.members.containsKey(_uid)) throw StateError('members only');
    final before = f.days[dayKey] ?? const FamilyDay();
    final after = change(before, f.days[yesterdayKey] ?? const FamilyDay());
    // As the rules: only your own letters, and a found word stays found.
    for (final e in after.found.entries) {
      if (e.key != _uid && !_sameList(before.found[e.key], e.value)) throw StateError('only your own letters');
    }
    if (before.solved && !after.solved) throw StateError('a found word stays found');
    f.days[dayKey] = after;
    server._changed();
    return after;
  }

  bool _sameList(List<int>? a, List<int> b) => a != null && a.length == b.length && [for (int i = 0; i < b.length; i++) a[i] == b[i]].every((x) => x);

  @override
  Future<void> updateBuildings(
    String familyId, {
    required Map<String, int> buildings,
    required List<String> newBuildings,
    required String newOn,
  }) async {
    server._check();
    final f = _family(familyId);
    final m = f.members[_uid];
    if (m == null) return;
    f.members[_uid] = m.copyWith(buildings: buildings, newBuildings: newBuildings, newOn: newOn);
    server._changed();
  }

  // ---- spec-10 ----

  @override
  Stream<List<FamilyNote>> watchNotes(String familyId, List<String> days) async* {
    final uid = _uid;
    List<FamilyNote>? read() {
      final f = server._families[familyId];
      if (f == null || !f.members.containsKey(uid)) return null;
      return [for (final n in f.notes.values) if (days.contains(n.day)) n];
    }

    final first = read();
    if (first == null) return;
    yield first;
    await for (final _ in server._changes.stream) {
      final n = read();
      if (n == null) return;
      yield n;
    }
  }

  @override
  Future<FamilyNote> sendNote(String familyId, FamilyNote note) async {
    server._check();
    final f = _family(familyId);
    // As the rules: members only, as yourself, to someone else in the family.
    if (!f.members.containsKey(_uid)) throw StateError('members only');
    if (note.from != _uid) throw StateError('only as yourself');
    if (note.to == _uid || !f.members.containsKey(note.to)) throw StateError('only to someone in the family');
    if (note.kind == NoteKind.gift && !RegExp(r'^[A-Z]$').hasMatch(note.letter ?? '')) throw StateError('one letter');
    final saved = note.withId(server.newId('n'));
    f.notes[saved.id] = saved;
    server._changed();
    return saved;
  }

  @override
  Future<void> cleanUpNotes(String familyId, List<String> keepDays) async {
    server._check();
    final f = _family(familyId);
    final uid = _uid;
    f.notes.removeWhere((_, n) => n.to == uid && !keepDays.contains(n.day));
    server._changed();
  }

  /// Every gift and cheer on the server, for tests.
  List<FamilyNote> allNotes(String familyId) => [...?server._families[familyId]?.notes.values];

  @override
  Future<void> setWants(String familyId, String? letter, String dayKey) async {
    server._check();
    final f = _family(familyId);
    final m = f.members[_uid];
    if (m == null) return;
    f.members[_uid] = letter == null ? m.copyWith(clearWants: true) : m.copyWith(wants: letter, wantsOn: dayKey);
    server._changed();
  }

  @override
  Future<String> newCode(String familyId) async {
    server._check();
    final f = _family(familyId);
    if (!_isAdult(f)) throw StateError('only grown-ups can change the code');
    server._codes.remove(f.code);
    f.code = server._uniqueCode();
    server._codes[f.code] = f.id;
    server._changed();
    return f.code;
  }

  @override
  Future<void> renameFamily(String familyId, String name) async {
    server._check();
    final f = _family(familyId);
    if (!_isAdult(f)) throw StateError('only grown-ups can rename the family');
    f.name = name;
    server._changed();
  }

  @override
  Future<void> removeMember(String familyId, String uid) async {
    server._check();
    final f = _family(familyId);
    if (uid != _uid && !_isAdult(f)) throw StateError('only grown-ups can remove someone');
    f.members.remove(uid);
    if (f.members.isEmpty) {
      server._families.remove(f.id);
      server._codes.remove(f.code);
    }
    server._changed();
  }

  @override
  Future<void> leave(String familyId) async {
    await removeMember(familyId, _uid);
    server.profiles[_uid]?['familyId'] = null;
  }

  @override
  Future<void> deleteAccount(String? familyId) async {
    server._check();
    if (familyId != null) {
      server._families[familyId]?.requests.remove(_uid);
      if (server._families[familyId]?.members.containsKey(_uid) ?? false) await leave(familyId);
    }
    server.profiles.remove(_uid);
    server._uidByEmail.removeWhere((_, uid) => uid == _uid);
    _account = null;
  }
}
