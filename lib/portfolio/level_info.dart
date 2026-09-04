// XP/level curve. Total XP is the single source of truth (persisted);
// level and progress-into-level are always derived from it, so there's
// never a stored level that can drift out of sync with stored XP.
class LevelInfo {
  final int level;
  final int xpIntoLevel;
  final int xpForNextLevel;

  const LevelInfo({
    required this.level,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
  });

  double get progress => xpForNextLevel == 0 ? 0 : xpIntoLevel / xpForNextLevel;
}

// XP required to go from `level` to `level + 1`. Increases each level so
// progress naturally slows down.
int xpRequiredForLevel(int level) => 100 + (level - 1) * 50;

LevelInfo levelInfoForXp(int totalXp) {
  int level = 1;
  int remaining = totalXp;
  int needed = xpRequiredForLevel(level);
  while (remaining >= needed) {
    remaining -= needed;
    level++;
    needed = xpRequiredForLevel(level);
  }
  return LevelInfo(level: level, xpIntoLevel: remaining, xpForNextLevel: needed);
}
