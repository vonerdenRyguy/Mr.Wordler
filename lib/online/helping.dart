// Helping each other (spec-10): letter gifts, asking for a letter, and
// ready-made cheers. The rules here are pure so tests can check them.

import 'family_online_models.dart';

/// Letter gifts each person can send a day, to anyone in the family.
const kGiftsPerDay = 3;

/// Gift tiles added to the village rack in one visit; more wait.
const kGiftsPerVisit = 5;

/// A cheer: a big picture and a word or two. Nothing is ever typed.
class Sticker {
  const Sticker(this.id, this.glyph, this.word);

  final String id;
  final String glyph;
  final String word;
}

const kStickers = [
  Sticker('wow', '⭐', 'Wow!'),
  Sticker('highfive', '✋', 'High five!'),
  Sticker('love', '❤️', 'Love it!'),
  Sticker('hooray', '\u{1F389}', 'Hooray!'),
  Sticker('team', '\u{1F44F}', 'Go team!'),
  Sticker('thanks', '\u{1F64F}', 'Thank you!'),
  Sticker('smart', '\u{1F9E0}', 'So smart!'),
  Sticker('strong', '\u{1F4AA}', 'Strong!'),
  Sticker('star', '\u{1F31F}', 'Superstar!'),
  Sticker('hug', '\u{1F917}', 'Big hug!'),
  Sticker('fire', '\u{1F525}', 'On fire!'),
  Sticker('rainbow', '\u{1F308}', 'Lovely!'),
];

const kThankYouSticker = 'thanks';

Sticker? stickerById(String? id) => kStickers.where((s) => s.id == id).firstOrNull;

/// How many gifts [uid] can still send on [dayKey].
int giftsLeft(List<FamilyNote> notes, String uid, String dayKey) {
  final sent = notes.where((n) => n.kind == NoteKind.gift && n.from == uid && n.day == dayKey).length;
  return (kGiftsPerDay - sent).clamp(0, kGiftsPerDay);
}

/// [member]'s open request on [dayKey]: the letter they asked for, unless
/// someone has already sent them one like it since asking.
String? openRequest(OnlineMember member, List<FamilyNote> notes, String dayKey) {
  final letter = member.wantsOnDay(dayKey);
  if (letter == null) return null;
  final answered = notes.any(
      (n) => n.kind == NoteKind.gift && n.to == member.uid && n.day == dayKey && n.letter == letter);
  return answered ? null : letter;
}

/// Gifts to [uid] that aren't in their rack yet, oldest first.
List<FamilyNote> waitingGifts(List<FamilyNote> notes, String uid, Set<String> claimed) {
  final list = [
    for (final n in notes)
      if (n.kind == NoteKind.gift && n.to == uid && n.letter != null && !claimed.contains(n.id)) n
  ]..sort((a, b) => a.at.compareTo(b.at));
  return list;
}

/// What the Home card lists for [uid]: gifts and cheers to them, and other
/// members' open requests, newest first.
class HelpItem {
  const HelpItem.note(FamilyNote this.note) : asker = null, letter = null;
  const HelpItem.request(OnlineMember this.asker, String this.letter) : note = null;

  final FamilyNote? note;
  final OnlineMember? asker;
  final String? letter;
}

List<HelpItem> helpItemsFor({
  required String uid,
  required List<OnlineMember> members,
  required List<FamilyNote> notes,
  required String dayKey,
}) {
  final mine = [for (final n in notes) if (n.to == uid) n]..sort((a, b) => b.at.compareTo(a.at));
  return [
    for (final m in members)
      if (m.uid != uid && openRequest(m, notes, dayKey) != null) HelpItem.request(m, openRequest(m, notes, dayKey)!),
    for (final n in mine) HelpItem.note(n),
  ];
}
