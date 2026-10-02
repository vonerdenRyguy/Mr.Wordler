import 'village_save.dart';

/// Brings an older save up to the current format. Version 1 -> 2: the rack
/// shrinks to [rackSize]. The first [rackSize] letters (in slot order,
/// skipping empties) stay in the rack; the rest go back to the pool and
/// leave dealtLetters. Board, pool order of existing letters, landmarks,
/// discovered words and lastCashedOutScore are untouched. Version 2 saves
/// are returned unchanged.
VillageSaveData migrateVillageSave(VillageSaveData data, {required int rackSize}) {
  if (data.saveVersion >= 2) return data;

  // Every slot, base and bonus alike, is handled the same way.
  final letters = data.rackCells.whereType<String>().toList();
  final kept = letters.take(rackSize).toList();
  final returned = letters.skip(rackSize).toList();

  final rack = <String?>[...kept, ...List<String?>.filled(rackSize - kept.length, null)];
  final dealt = List<String>.from(data.dealtLetters);
  for (final letter in returned) {
    dealt.remove(letter);
  }

  return VillageSaveData(
    boardCells: data.boardCells,
    rackCells: rack,
    pool: [...data.pool, ...returned],
    dealtLetters: dealt,
    lastCashedOutScore: data.lastCashedOutScore,
    reachedLandmarks: data.reachedLandmarks,
    discoveredWords: data.discoveredWords,
    saveVersion: 2,
  );
}
