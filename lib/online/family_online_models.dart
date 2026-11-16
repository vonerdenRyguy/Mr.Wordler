import 'dart:math';

import '../settings/word_level.dart';

// Family online (spec-08): the shapes of the data that live on the server,
// and the one interface the app talks to. FirebaseFamilyBackend is the real
// one; FakeFamilyBackend is an in-memory stand-in for tests.
//
// What goes online is only the shared bits: first name, color, word level,
// grown-up or not, and the day someone last played. Villages, coins and
// puzzles stay on each phone.

/// How old someone is, which decides how they get in.
enum AgeGroup {
  /// Under 13: never gives an email; a grown-up's yes lets them in.
  child,

  /// 13 to 17: signs in, but can't say yes for others.
  teen,

  /// 18 and over: can start a family and say yes to new members.
  adult,
}

AgeGroup ageGroupFor({required int birthYear, required int birthMonth, required DateTime now}) {
  var age = now.year - birthYear;
  if (now.month < birthMonth) age -= 1;
  if (age < 13) return AgeGroup.child;
  if (age < 18) return AgeGroup.teen;
  return AgeGroup.adult;
}

AgeGroup? ageGroupFromName(String? name) {
  for (final g in AgeGroup.values) {
    if (g.name == name) return g;
  }
  return null;
}

enum SignInMethod { google, email, child }

class OnlineAccount {
  const OnlineAccount({required this.uid, required this.method, this.email});

  final String uid;
  final SignInMethod method;
  final String? email;

  /// "n•••@example.com": enough to recognise, not enough to read out.
  String? get maskedEmail {
    final e = email;
    if (e == null || !e.contains('@')) return null;
    final at = e.indexOf('@');
    return '${e.substring(0, 1)}•••${e.substring(at)}';
  }
}

/// What a player shares when they ask to join.
class MemberInfo {
  const MemberInfo({required this.name, required this.colorIndex, required this.level});

  final String name;
  final int colorIndex;
  final WordLevel level;
}

class OnlineMember {
  const OnlineMember({
    required this.uid,
    required this.name,
    required this.colorIndex,
    required this.level,
    required this.adult,
    this.playedDay,
  });

  final String uid;
  final String name;
  final int colorIndex;
  final WordLevel level;

  /// A grown-up: can say yes to new members and change the code.
  final bool adult;

  /// The UTC day (dailyDateKey) this member last finished a Daily.
  final String? playedDay;

  bool playedOn(String dayKey) => playedDay == dayKey;
}

class JoinRequest {
  const JoinRequest({
    required this.uid,
    required this.name,
    required this.colorIndex,
    required this.level,
    required this.birthYear,
    required this.group,
  });

  final String uid;
  final String name;
  final int colorIndex;
  final WordLevel level;
  final int birthYear;
  final AgeGroup group;
}

class OnlineFamily {
  const OnlineFamily({
    required this.id,
    required this.name,
    required this.code,
    required this.members,
    this.requests = const [],
  });

  final String id;
  final String name;
  final String code;
  final List<OnlineMember> members;

  /// Only filled in for grown-ups (nobody else may read them).
  final List<JoinRequest> requests;

  OnlineMember? member(String uid) {
    for (final m in members) {
      if (m.uid == uid) return m;
    }
    return null;
  }
}

/// What someone with the code sees before asking to join: the family's
/// name and its grown-ups' first names. Never the children's.
class FamilyPreview {
  const FamilyPreview({required this.familyId, required this.name, required this.adultNames});

  final String familyId;
  final String name;
  final List<String> adultNames;
}

/// Where a request to join stands, seen from the person who asked.
enum RequestStatus { waiting, accepted, declined }

/// The one way the app reaches the server. One instance per player on the
/// phone, so each player keeps their own sign-in.
abstract class FamilyBackend {
  /// The account this player is signed in with, if any.
  OnlineAccount? get account;

  /// Null when the person backed out of the Google sheet.
  Future<OnlineAccount?> signInWithGoogle();

  Future<void> sendEmailLink(String email);
  bool isEmailLink(String link);
  Future<OnlineAccount> finishEmailLink({required String email, required String link});

  /// For children under 13: an account with no email or name attached.
  Future<OnlineAccount> signInAsChild();

  Future<void> signOut();

  /// Saves the account's own birth year, age group and family (only this
  /// account can read it back).
  Future<void> saveProfile({int? birthYear, AgeGroup? group, String? familyId});

  /// Starts a family with this (grown-up) account as its first member.
  Future<OnlineFamily> createFamily({required String name, required MemberInfo me});

  Future<FamilyPreview?> findFamily(String code);

  Future<void> requestToJoin({
    required FamilyPreview family,
    required String code,
    required MemberInfo me,
    required int birthYear,
    required AgeGroup group,
  });

  Future<void> cancelRequest(String familyId);
  Stream<RequestStatus> watchRequest(String familyId);

  /// The family as it changes; ends with null if this account is removed.
  Stream<OnlineFamily?> watchFamily(String familyId);

  Future<void> approve(String familyId, JoinRequest request);
  Future<void> decline(String familyId, JoinRequest request);
  Future<void> updateMe(String familyId, MemberInfo me);
  Future<void> setPlayedDay(String familyId, String dayKey);
  Future<String> newCode(String familyId);
  Future<void> renameFamily(String familyId, String name);
  Future<void> removeMember(String familyId, String uid);
  Future<void> leave(String familyId);

  /// Leaves the family (if any) and deletes the account and its profile.
  Future<void> deleteAccount(String? familyId);
}

// ---- Family codes ----------------------------------------------------------

/// Friendly words for the first half of a family code: easy to read out to
/// Nana over the phone, and nothing that could spell something rude.
const kCodeWords = [
  'BEAR', 'LION', 'FROG', 'DUCK', 'SEAL', 'WOLF', 'DEER', 'GOAT', 'LAMB', 'MOLE', //
  'CRAB', 'FISH', 'BIRD', 'MOON', 'STAR', 'TREE', 'LEAF', 'ROSE', 'SNOW', 'RAIN',
  'CAKE', 'PEAR', 'PLUM', 'KIWI', 'LAKE', 'HILL', 'SAND', 'BOAT', 'KITE', 'DRUM',
  'BELL', 'NEST', 'SEED', 'CORN', 'MINT', 'WAVE', 'POND', 'SHIP', 'LAMP', 'COAT',
];

/// A code like BEAR4821: a word and four digits (no 0 or 1, which look like
/// O and I).
String newFamilyCode(Random random) {
  final word = kCodeWords[random.nextInt(kCodeWords.length)];
  final digits = List.generate(4, (_) => 2 + random.nextInt(8)).join();
  return '$word$digits';
}

/// Uppercases, drops spaces and dashes. Null unless it looks like a code.
String? normalizeFamilyCode(String input) {
  final code = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return RegExp(r'^[A-Z]{4}[0-9]{4}$').hasMatch(code) ? code : null;
}

/// BEAR4821 -> "BEAR 4821".
String showFamilyCode(String code) => code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;
