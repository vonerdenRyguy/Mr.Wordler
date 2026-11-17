import 'dart:math';

import '../settings/word_level.dart';
import 'town_square.dart';

export 'town_square.dart';

// Family online (spec-08): the shapes of the data that live on the server,
// and the one interface the app talks to. FirebaseFamilyBackend is the real
// one; FakeFamilyBackend is an in-memory stand-in for tests.
//
// What goes online is only the shared bits: first name, color, word level,
// grown-up or not, and the day someone last played; since spec-09 also the
// family word's letters and each member's list of buildings. Villages'
// words, coins and puzzles stay on each phone.

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
    this.buildings = const {},
    this.newBuildings = const [],
    this.newOn,
    this.wants,
    this.wantsOn,
  });

  final String uid;
  final String name;
  final int colorIndex;
  final WordLevel level;

  /// A grown-up: can say yes to new members and change the code.
  final bool adult;

  /// The UTC day (dailyDateKey) this member last finished a Daily.
  final String? playedDay;

  /// The buildings in this member's village: magic word -> how many
  /// (spec-09). Only this summary is shared, never the village itself.
  final Map<String, int> buildings;

  /// Buildings raised on the day [newOn].
  final List<String> newBuildings;
  final String? newOn;

  /// The letter this member asked the family for (spec-10), on [wantsOn].
  final String? wants;
  final String? wantsOn;

  bool playedOn(String dayKey) => playedDay == dayKey;

  /// Their request, if it's from [dayKey] (requests last one day).
  String? wantsOnDay(String dayKey) => wantsOn == dayKey ? wants : null;

  OnlineMember copyWith({
    String? name,
    int? colorIndex,
    WordLevel? level,
    String? playedDay,
    Map<String, int>? buildings,
    List<String>? newBuildings,
    String? newOn,
    String? wants,
    String? wantsOn,
    bool clearWants = false,
  }) =>
      OnlineMember(
        uid: uid,
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        level: level ?? this.level,
        adult: adult,
        playedDay: playedDay ?? this.playedDay,
        buildings: buildings ?? this.buildings,
        newBuildings: newBuildings ?? this.newBuildings,
        newOn: newOn ?? this.newOn,
        wants: clearWants ? null : (wants ?? this.wants),
        wantsOn: clearWants ? null : (wantsOn ?? this.wantsOn),
      );

  int get buildingCount => buildings.values.fold(0, (a, b) => a + b);

  List<String> newOnDay(String dayKey) => newOn == dayKey ? newBuildings : const [];
}

/// One day of the family word, online (spec-09). The word itself isn't
/// stored: every phone works it out from the date.
class FamilyDay {
  const FamilyDay({
    this.found = const {},
    this.solved = false,
    this.solvedEarly = false,
    this.solvedBy,
    this.streak = 0,
  });

  /// Letter positions uncovered, by the uid of the member who found them.
  final Map<String, List<int>> found;
  final bool solved;

  /// Found by a guess before all the letters were out.
  final bool solvedEarly;

  /// Who guessed it, or who uncovered the last letters.
  final String? solvedBy;

  /// Days in a row (this one included) the family found the word.
  final int streak;

  Set<int> get revealed => {for (final list in found.values) ...list};

  String? finderOf(int index) {
    for (final e in found.entries) {
      if (e.value.contains(index)) return e.key;
    }
    return null;
  }

  Map<String, dynamic> toData() => {
        'found': found,
        'solved': solved,
        'solvedEarly': solvedEarly,
        if (solvedBy != null) 'solvedBy': solvedBy,
        'streak': streak,
      };

  factory FamilyDay.fromData(Map<String, dynamic>? data) {
    if (data == null) return const FamilyDay();
    return FamilyDay(
      found: {
        for (final e in (data['found'] as Map? ?? const {}).entries)
          e.key as String: [for (final i in e.value as List) (i as num).toInt()],
      },
      solved: data['solved'] as bool? ?? false,
      solvedEarly: data['solvedEarly'] as bool? ?? false,
      solvedBy: data['solvedBy'] as String?,
      streak: (data['streak'] as num?)?.toInt() ?? 0,
    );
  }
}

/// [uid] finishes their Daily: the day as it is afterwards. Their share is
/// the hidden letters (in [revealOrder]) split between everyone in
/// [memberUids] who hasn't played yet, rounded up, so the order people
/// play in never matters and the last one uncovers the rest. [yesterday]
/// carries the streak on.
FamilyDay uncoverShare(
  FamilyDay day, {
  required String uid,
  required List<int> revealOrder,
  required List<String> memberUids,
  FamilyDay? yesterday,
}) {
  if (day.solved || day.found.containsKey(uid)) return day;
  final revealed = day.revealed;
  final hidden = [for (final i in revealOrder) if (!revealed.contains(i)) i];
  final everyone = {...memberUids, uid};
  final stillToPlay = everyone.where((u) => !day.found.containsKey(u)).length;
  final share = hidden.take((hidden.length / (stillToPlay < 1 ? 1 : stillToPlay)).ceil()).toList();
  final found = {...day.found, uid: share};
  final done = {for (final l in found.values) ...l}.length >= revealOrder.length;
  return FamilyDay(
    found: found,
    solved: done,
    solvedBy: done ? uid : null,
    streak: done ? _streakAfter(yesterday) : 0,
  );
}

/// A right guess: the day, found early (unchanged if already found).
FamilyDay solveByGuess(FamilyDay day, {required String uid, FamilyDay? yesterday}) {
  if (day.solved) return day;
  return FamilyDay(
    found: day.found,
    solved: true,
    solvedEarly: true,
    solvedBy: uid,
    streak: _streakAfter(yesterday),
  );
}

int _streakAfter(FamilyDay? yesterday) => (yesterday != null && yesterday.solved ? yesterday.streak : 0) + 1;

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
  /// account can read it back). The family is left as it is unless
  /// [familyId] is given or [clearFamily] is set.
  Future<void> saveProfile({int? birthYear, AgeGroup? group, String? familyId, bool clearFamily = false});

  /// The family this account last joined, read back from its own profile:
  /// how a grown-up who signs out and back in finds their family again.
  Future<String?> savedFamilyId();

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

  // ---- The family word and map (spec-09) ----

  /// One day of the family word as it changes (an empty day until someone
  /// plays).
  Stream<FamilyDay> watchDay(String familyId, String dayKey);
  Future<FamilyDay> getDay(String familyId, String dayKey);

  /// Applies [change] to the day [dayKey] in one step on the server (so two
  /// phones finishing at once can't both take the same letters), reading
  /// [yesterdayKey] for the streak. Returns the day as saved.
  Future<FamilyDay> changeDay(
    String familyId,
    String dayKey, {
    required String yesterdayKey,
    required FamilyDay Function(FamilyDay today, FamilyDay yesterday) change,
  });

  /// Shares this account's buildings with the family.
  Future<void> updateBuildings(
    String familyId, {
    required Map<String, int> buildings,
    required List<String> newBuildings,
    required String newOn,
  });

  // ---- Helping (spec-10) ----

  /// The family's gifts and cheers from [days] (today and yesterday), as
  /// they change.
  Stream<List<FamilyNote>> watchNotes(String familyId, List<String> days);

  /// Sends a gift or cheer from this account. Returns it with its id.
  Future<FamilyNote> sendNote(String familyId, FamilyNote note);

  /// Deletes gifts and cheers sent to this account that aren't from
  /// [keepDays], so old ones don't pile up.
  Future<void> cleanUpNotes(String familyId, List<String> keepDays);

  /// Asks the family for [letter] today, or takes the request back (null).
  Future<void> setWants(String familyId, String? letter, String dayKey);

  // ---- The Town Square (spec-13) ----

  /// The family's Town Square as it changes (empty until someone adds to it).
  Stream<TownSquare> watchSquare(String familyId);

  /// Applies [change] to the Town Square in one step on the server, so
  /// bricks from two phones at once both count. Returns it as saved.
  Future<TownSquare> changeSquare(String familyId, TownSquare Function(TownSquare square) change);
}

enum NoteKind { gift, cheer }

/// A gift (a letter for someone's village rack) or a cheer (a sticker)
/// from one family member to another (spec-10). Nothing is ever typed.
class FamilyNote {
  const FamilyNote({
    this.id = '',
    required this.kind,
    required this.from,
    required this.to,
    required this.day,
    this.letter,
    this.sticker,
    this.about,
    this.at = 0,
  });

  final String id;
  final NoteKind kind;
  final String from;
  final String to;

  /// The UTC day it was sent (dailyDateKey).
  final String day;

  /// A gift's letter, A-Z.
  final String? letter;

  /// A cheer's sticker id (see kStickers).
  final String? sticker;

  /// What a cheer is for: a building's word, or "family word". Optional.
  final String? about;

  /// When it was sent, in milliseconds since 1970 (for newest first).
  final int at;

  Map<String, Object?> toData() => {
        'kind': kind.name,
        'from': from,
        'to': to,
        'day': day,
        if (letter != null) 'letter': letter,
        if (sticker != null) 'sticker': sticker,
        if (about != null) 'about': about,
        'at': at,
      };

  static FamilyNote? fromData(String id, Map<String, Object?> d) {
    final kind = NoteKind.values.where((k) => k.name == d['kind']).firstOrNull;
    final from = d['from'], to = d['to'], day = d['day'];
    if (kind == null || from is! String || to is! String || day is! String) return null;
    return FamilyNote(
      id: id,
      kind: kind,
      from: from,
      to: to,
      day: day,
      letter: d['letter'] as String?,
      sticker: d['sticker'] as String?,
      about: d['about'] as String?,
      at: (d['at'] as num?)?.toInt() ?? 0,
    );
  }

  FamilyNote withId(String id) => FamilyNote(
      id: id, kind: kind, from: from, to: to, day: day, letter: letter, sticker: sticker, about: about, at: at);
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
