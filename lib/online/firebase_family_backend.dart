import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../players/players.dart';
import '../settings/word_level.dart';
import 'family_online_models.dart';

// The real family server: Firebase Authentication and Cloud Firestore,
// following firebase/firestore.rules. Each player on the phone gets their
// own named FirebaseApp, so each keeps their own sign-in (the first player
// uses the default app).

/// True once Firebase.initializeApp() worked in main(). False in tests and
/// on a build made without google-services.json.
bool firebaseReady = false;

const kAndroidPackage = 'com.example.namer_app';

/// The sign-in needs a fresh sign-in first (asked for before deleting).
class RecentSignInNeeded implements Exception {
  const RecentSignInNeeded();
}

class FirebaseFamilyBackend implements FamilyBackend {
  FirebaseFamilyBackend._(this._app)
      : _auth = FirebaseAuth.instanceFor(app: _app),
        _db = FirebaseFirestore.instanceFor(app: _app);

  static Future<FirebaseFamilyBackend> forPlayer(String playerId) async {
    if (playerId == kFirstPlayerId) return FirebaseFamilyBackend._(Firebase.app());
    final name = 'player_$playerId';
    for (final app in Firebase.apps) {
      if (app.name == name) return FirebaseFamilyBackend._(app);
    }
    final app = await Firebase.initializeApp(name: name, options: Firebase.app().options);
    return FirebaseFamilyBackend._(app);
  }

  final FirebaseApp _app;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final _random = Random.secure();

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError('not signed in');
    return u.uid;
  }

  DocumentReference<Map<String, dynamic>> _family(String fid) => _db.collection('families').doc(fid);
  DocumentReference<Map<String, dynamic>> _member(String fid, String uid) =>
      _family(fid).collection('members').doc(uid);
  DocumentReference<Map<String, dynamic>> _request(String fid, String uid) =>
      _family(fid).collection('requests').doc(uid);
  DocumentReference<Map<String, dynamic>> _code(String code) => _db.collection('codes').doc(code);
  DocumentReference<Map<String, dynamic>> _profile(String uid) => _db.collection('users').doc(uid);

  OnlineAccount? _toAccount(User? u) {
    if (u == null) return null;
    final SignInMethod method;
    if (u.isAnonymous) {
      method = SignInMethod.child;
    } else if (u.providerData.any((p) => p.providerId == 'google.com')) {
      method = SignInMethod.google;
    } else {
      method = SignInMethod.email;
    }
    return OnlineAccount(uid: u.uid, method: method, email: u.email);
  }

  @override
  OnlineAccount? get account => _toAccount(_auth.currentUser);

  Future<AuthCredential?> _googleCredential() async {
    final google = GoogleSignIn(scopes: const ['email']);
    // Always show the account chooser, so each player picks their own.
    await google.signOut();
    final picked = await google.signIn();
    if (picked == null) return null;
    final tokens = await picked.authentication;
    await google.signOut();
    return GoogleAuthProvider.credential(idToken: tokens.idToken, accessToken: tokens.accessToken);
  }

  @override
  Future<OnlineAccount?> signInWithGoogle() async {
    final credential = await _googleCredential();
    if (credential == null) return null;
    final result = await _auth.signInWithCredential(credential);
    return _toAccount(result.user);
  }

  ActionCodeSettings get _linkSettings => ActionCodeSettings(
        url: 'https://${_app.options.projectId}.firebaseapp.com/finishSignIn',
        handleCodeInApp: true,
        androidPackageName: kAndroidPackage,
        androidInstallApp: true,
        androidMinimumVersion: '1',
      );

  @override
  Future<void> sendEmailLink(String email) =>
      _auth.sendSignInLinkToEmail(email: email, actionCodeSettings: _linkSettings);

  @override
  bool isEmailLink(String link) => _auth.isSignInWithEmailLink(link);

  @override
  Future<OnlineAccount> finishEmailLink({required String email, required String link}) async {
    final result = await _auth.signInWithEmailLink(email: email, emailLink: link);
    return _toAccount(result.user)!;
  }

  @override
  Future<OnlineAccount> signInAsChild() async {
    final result = await _auth.signInAnonymously();
    return _toAccount(result.user)!;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> saveProfile({int? birthYear, AgeGroup? group, String? familyId, bool clearFamily = false}) =>
      _profile(_uid).set({
        if (birthYear != null) 'birthYear': birthYear,
        if (group != null) 'group': group.name,
        if (familyId != null || clearFamily) 'familyId': familyId,
      }, SetOptions(merge: true));

  @override
  Future<String?> savedFamilyId() async {
    final snap = await _profile(_uid).get();
    return snap.data()?['familyId'] as String?;
  }

  Future<String> _freeCode() async {
    for (int i = 0; i < 20; i++) {
      final code = newFamilyCode(_random);
      final snap = await _code(code).get();
      if (!snap.exists) return code;
    }
    throw StateError('could not find a free family code');
  }

  Map<String, dynamic> _memberData(MemberInfo me, {required bool adult, String? joinCode}) => {
        'name': me.name,
        'colorIndex': me.colorIndex,
        'level': me.level.name,
        'adult': adult,
        if (joinCode != null) 'joinCode': joinCode,
        'joinedAt': FieldValue.serverTimestamp(),
      };

  @override
  Future<OnlineFamily> createFamily({required String name, required MemberInfo me}) async {
    final uid = _uid;
    final ref = _db.collection('families').doc();
    final code = await _freeCode();
    final batch = _db.batch()
      ..set(ref, {'name': name, 'code': code, 'createdBy': uid, 'createdAt': FieldValue.serverTimestamp()})
      ..set(_member(ref.id, uid), _memberData(me, adult: true, joinCode: code))
      ..set(_code(code), {
        'familyId': ref.id,
        'familyName': name,
        'adultNames': [me.name],
      })
      ..set(_profile(uid), {'familyId': ref.id}, SetOptions(merge: true));
    await batch.commit();
    return OnlineFamily(
      id: ref.id,
      name: name,
      code: code,
      members: [OnlineMember(uid: uid, name: me.name, colorIndex: me.colorIndex, level: me.level, adult: true)],
    );
  }

  @override
  Future<FamilyPreview?> findFamily(String code) async {
    final snap = await _code(code).get();
    final data = snap.data();
    if (data == null) return null;
    return FamilyPreview(
      familyId: data['familyId'] as String,
      name: data['familyName'] as String? ?? 'Your family',
      adultNames: [for (final n in (data['adultNames'] as List? ?? const [])) n as String],
    );
  }

  @override
  Future<void> requestToJoin({
    required FamilyPreview family,
    required String code,
    required MemberInfo me,
    required int birthYear,
    required AgeGroup group,
  }) =>
      _request(family.familyId, _uid).set({
        'name': me.name,
        'colorIndex': me.colorIndex,
        'level': me.level.name,
        'birthYear': birthYear,
        'group': group.name,
        'joinCode': code,
        'at': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> cancelRequest(String familyId) => _request(familyId, _uid).delete();

  @override
  Stream<RequestStatus> watchRequest(String familyId) async* {
    final uid = _uid;
    await for (final snap in _request(familyId, uid).snapshots()) {
      if (snap.exists) {
        yield RequestStatus.waiting;
        continue;
      }
      // The request is gone: either a grown-up said yes (and we can now
      // read our member page) or they said not now.
      try {
        final member = await _member(familyId, uid).get();
        yield member.exists ? RequestStatus.accepted : RequestStatus.declined;
      } on FirebaseException {
        yield RequestStatus.declined;
      }
    }
  }

  OnlineMember _toMember(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const {};
    return OnlineMember(
      uid: d.id,
      name: data['name'] as String? ?? 'Player',
      colorIndex: (data['colorIndex'] as num?)?.toInt() ?? 0,
      level: wordLevelFromName(data['level'] as String?) ?? WordLevel.wordsmith,
      adult: data['adult'] as bool? ?? false,
      playedDay: data['playedDay'] as String?,
      buildings: {
        for (final e in (data['buildings'] as Map? ?? const {}).entries)
          e.key as String: (e.value as num?)?.toInt() ?? 0,
      },
      newBuildings: [for (final w in (data['newBuildings'] as List? ?? const [])) w as String],
      newOn: data['newOn'] as String?,
      wants: data['wants'] as String?,
      wantsOn: data['wantsOn'] as String?,
    );
  }

  JoinRequest _toRequest(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const {};
    return JoinRequest(
      uid: d.id,
      name: data['name'] as String? ?? 'Player',
      colorIndex: (data['colorIndex'] as num?)?.toInt() ?? 0,
      level: wordLevelFromName(data['level'] as String?) ?? WordLevel.wordsmith,
      birthYear: (data['birthYear'] as num?)?.toInt() ?? 0,
      group: ageGroupFromName(data['group'] as String?) ?? AgeGroup.child,
    );
  }

  @override
  Stream<OnlineFamily?> watchFamily(String familyId) {
    final uid = _uid;
    late final StreamController<OnlineFamily?> out;
    final subs = <StreamSubscription<Object?>>[];
    DocumentSnapshot<Map<String, dynamic>>? family;
    QuerySnapshot<Map<String, dynamic>>? members;
    QuerySnapshot<Map<String, dynamic>>? requests;
    var watchingRequests = false;

    void emit() {
      if (out.isClosed) return;
      final f = family;
      final m = members;
      if (f == null || m == null) return;
      final data = f.data();
      final list = [for (final d in m.docs) _toMember(d)];
      final me = list.where((x) => x.uid == uid).firstOrNull;
      if (data == null || me == null) {
        out.add(null);
        return;
      }
      if (me.adult && !watchingRequests) {
        watchingRequests = true;
        subs.add(_family(familyId).collection('requests').snapshots().listen((s) {
          requests = s;
          emit();
        }, onError: (Object _) {}));
      }
      out.add(OnlineFamily(
        id: familyId,
        name: data['name'] as String? ?? 'Your family',
        code: data['code'] as String? ?? '',
        members: list,
        requests: [for (final d in requests?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) _toRequest(d)],
      ));
    }

    // Permission errors mean this account is no longer in the family.
    void gone(Object _) {
      if (!out.isClosed) out.add(null);
    }

    out = StreamController<OnlineFamily?>(
      onListen: () {
        subs.add(_family(familyId).snapshots().listen((s) {
          family = s;
          emit();
        }, onError: gone));
        subs.add(_family(familyId).collection('members').snapshots().listen((s) {
          members = s;
          emit();
        }, onError: gone));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return out.stream;
  }

  @override
  Future<void> approve(String familyId, JoinRequest request) async {
    final adult = request.group == AgeGroup.adult;
    final me = MemberInfo(name: request.name, colorIndex: request.colorIndex, level: request.level);
    final family = await _family(familyId).get();
    final code = family.data()?['code'] as String?;
    final batch = _db.batch()
      ..set(_member(familyId, request.uid), _memberData(me, adult: adult))
      ..delete(_request(familyId, request.uid));
    if (adult && code != null) {
      batch.update(_code(code), {
        'adultNames': FieldValue.arrayUnion([request.name]),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> decline(String familyId, JoinRequest request) => _request(familyId, request.uid).delete();

  @override
  Future<void> updateMe(String familyId, MemberInfo me) => _member(familyId, _uid).update({
        'name': me.name,
        'colorIndex': me.colorIndex,
        'level': me.level.name,
      });

  @override
  Future<void> setPlayedDay(String familyId, String dayKey) =>
      _member(familyId, _uid).update({'playedDay': dayKey});

  // ---- The family word and map (spec-09) ----

  DocumentReference<Map<String, dynamic>> _day(String fid, String dayKey) =>
      _family(fid).collection('days').doc(dayKey);

  @override
  Stream<FamilyDay> watchDay(String familyId, String dayKey) =>
      _day(familyId, dayKey).snapshots().map((s) => FamilyDay.fromData(s.data()));

  @override
  Future<FamilyDay> getDay(String familyId, String dayKey) async =>
      FamilyDay.fromData((await _day(familyId, dayKey).get()).data());

  @override
  Future<FamilyDay> changeDay(
    String familyId,
    String dayKey, {
    required String yesterdayKey,
    required FamilyDay Function(FamilyDay today, FamilyDay yesterday) change,
  }) =>
      _db.runTransaction((tx) async {
        final today = await tx.get(_day(familyId, dayKey));
        final yesterday = await tx.get(_day(familyId, yesterdayKey));
        final after = change(FamilyDay.fromData(today.data()), FamilyDay.fromData(yesterday.data()));
        tx.set(_day(familyId, dayKey), after.toData());
        return after;
      });

  @override
  Future<void> updateBuildings(
    String familyId, {
    required Map<String, int> buildings,
    required List<String> newBuildings,
    required String newOn,
  }) =>
      _member(familyId, _uid).update({
        'buildings': buildings,
        'newBuildings': newBuildings,
        'newOn': newOn,
      });

  // ---- Helping (spec-10) ----

  CollectionReference<Map<String, dynamic>> _notes(String fid) => _family(fid).collection('notes');

  @override
  Stream<List<FamilyNote>> watchNotes(String familyId, List<String> days) =>
      _notes(familyId).where('day', whereIn: days).snapshots().map((s) => [
            for (final d in s.docs)
              if (FamilyNote.fromData(d.id, d.data()) case final note?) note,
          ]);

  @override
  Future<FamilyNote> sendNote(String familyId, FamilyNote note) async {
    final ref = _notes(familyId).doc();
    await ref.set(note.toData());
    return note.withId(ref.id);
  }

  @override
  Future<void> cleanUpNotes(String familyId, List<String> keepDays) async {
    final old = await _notes(familyId).where('to', isEqualTo: _uid).get();
    final batch = _db.batch();
    var n = 0;
    for (final d in old.docs) {
      if (keepDays.contains(d.data()['day']) || n >= 400) continue;
      batch.delete(d.reference);
      n++;
    }
    if (n > 0) await batch.commit();
  }

  @override
  Future<void> setWants(String familyId, String? letter, String dayKey) => _member(familyId, _uid).update({
        'wants': letter ?? FieldValue.delete(),
        'wantsOn': letter == null ? FieldValue.delete() : dayKey,
      });

  Future<List<String>> _adultNames(String familyId) async {
    final members = await _family(familyId).collection('members').get();
    return [for (final d in members.docs) if (_toMember(d).adult) _toMember(d).name];
  }

  @override
  Future<String> newCode(String familyId) async {
    final family = await _family(familyId).get();
    final data = family.data() ?? const {};
    final oldCode = data['code'] as String?;
    final code = await _freeCode();
    final batch = _db.batch()
      ..update(_family(familyId), {'code': code})
      ..set(_code(code), {
        'familyId': familyId,
        'familyName': data['name'] ?? 'Your family',
        'adultNames': await _adultNames(familyId),
      });
    if (oldCode != null) batch.delete(_code(oldCode));
    await batch.commit();
    return code;
  }

  @override
  Future<void> renameFamily(String familyId, String name) async {
    final family = await _family(familyId).get();
    final code = family.data()?['code'] as String?;
    final batch = _db.batch()..update(_family(familyId), {'name': name});
    if (code != null) batch.update(_code(code), {'familyName': name});
    await batch.commit();
  }

  @override
  Future<void> removeMember(String familyId, String uid) async {
    final family = await _family(familyId).get();
    final code = family.data()?['code'] as String?;
    final members = await _family(familyId).collection('members').get();
    final leaving = members.docs.where((d) => d.id == uid).map(_toMember).firstOrNull;
    if (leaving == null) return;
    final batch = _db.batch()..delete(_member(familyId, uid));
    if (members.docs.length == 1) {
      // The last one out closes the family, and its family-word days and
      // gifts and cheers go too.
      final days = await _family(familyId).collection('days').get();
      final notes = await _notes(familyId).get();
      for (final d in [...days.docs, ...notes.docs].take(450)) {
        batch.delete(d.reference);
      }
      batch.delete(_family(familyId));
      if (code != null) batch.delete(_code(code));
    } else if (leaving.adult && code != null) {
      batch.update(_code(code), {
        'adultNames': FieldValue.arrayRemove([leaving.name]),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> leave(String familyId) async {
    await removeMember(familyId, _uid);
    await _profile(_uid).set({'familyId': null}, SetOptions(merge: true));
  }

  @override
  Future<void> deleteAccount(String? familyId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    // Firebase only deletes an account that signed in a few minutes ago.
    // Check that first, so a cancelled Google sheet can't leave the family
    // closed and the profile gone with the account still there.
    final lastSignIn = user.metadata.lastSignInTime;
    final recent = lastSignIn != null && DateTime.now().difference(lastSignIn) < const Duration(minutes: 4);
    if (!recent && !user.isAnonymous) {
      if (!user.providerData.any((p) => p.providerId == 'google.com')) throw const RecentSignInNeeded();
      final credential = await _googleCredential();
      if (credential == null) throw const RecentSignInNeeded();
      await user.reauthenticateWithCredential(credential);
    }
    if (familyId != null) {
      try {
        await _request(familyId, user.uid).delete();
      } on FirebaseException {
        // Not waiting to join; nothing to delete.
      }
      try {
        await removeMember(familyId, user.uid);
      } on FirebaseException {
        // Already out of the family.
      }
    }
    await _profile(user.uid).delete();
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;
      if (user.providerData.any((p) => p.providerId == 'google.com')) {
        final credential = await _googleCredential();
        if (credential == null) throw const RecentSignInNeeded();
        await user.reauthenticateWithCredential(credential);
        await user.delete();
      } else {
        throw const RecentSignInNeeded();
      }
    }
  }
}
