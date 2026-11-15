import '../portfolio/property_tier.dart';

String _tierEmoji(PropertyTier tier) {
  switch (tier) {
    case PropertyTier.mansion:
      return '\u{1F3F0}';
    case PropertyTier.house:
      return '\u{1F3E0}';
    case PropertyTier.cottage:
      return '\u{1F6D6}';
    case PropertyTier.vacantLot:
      return '\u{1F331}';
    case PropertyTier.empty:
      return '\u{274C}';
  }
}

String _formatSeconds(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// Wordle-style copy/paste-able result summary. Deliberately never
// includes the secret word itself -- only the theme and whether it was
// found -- so sharing a result doesn't spoil the puzzle for people who
// haven't played yet.
String buildDailyShareText({
  required String dateKey,
  required bool completed,
  required int timeSeconds,
  required int streak,
  required PropertyTier tier,
  required bool bonusWordFound,
  String? themeName,
  int cluesUsed = 0,
}) {
  final buffer = StringBuffer()
    ..writeln('Mr. Wordler \u{2014} Daily puzzle')
    ..writeln(dateKey);
  if (themeName != null) buffer.writeln('Theme: $themeName');

  final days = '\u{1F525} $streak day${streak == 1 ? '' : 's'}';
  if (!completed) {
    buffer.write('\u{274C} Gave up today   $days');
    return buffer.toString();
  }

  buffer.writeln('\u{23F1}\u{FE0F} ${_formatSeconds(timeSeconds)}   $days   ${_tierEmoji(tier)} ${tier.label}');
  if (bonusWordFound) {
    buffer.write('\u{2728} Secret word found!${cluesUsed == 0 ? ' (no clues)' : ''}');
  }
  return buffer.toString().trim();
}
