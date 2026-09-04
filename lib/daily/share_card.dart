import '../portfolio/property_tier.dart';

String _tierEmoji(PropertyTier tier) {
  switch (tier) {
    case PropertyTier.mansion:
      return '🏰';
    case PropertyTier.house:
      return '🏠';
    case PropertyTier.cottage:
      return '🛖';
    case PropertyTier.vacantLot:
      return '🌱';
    case PropertyTier.empty:
      return '❌';
  }
}

String _formatSeconds(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// Wordle-style copy/paste-able result summary. Deliberately never
// includes the actual bonus word text -- only whether it was found --
// so sharing a result doesn't spoil the puzzle for people who haven't
// played yet.
String buildDailyShareText({
  required String dateKey,
  required bool completed,
  required int timeSeconds,
  required int streak,
  required PropertyTier tier,
  required bool bonusWordFound,
}) {
  final buffer = StringBuffer()
    ..writeln('Mr. Wordler — Daily Estate Challenge')
    ..writeln(dateKey);

  if (!completed) {
    buffer.write('❌ Gave up today   🔥 $streak day${streak == 1 ? '' : 's'}');
    return buffer.toString();
  }

  buffer.writeln(
      '⏱️ ${_formatSeconds(timeSeconds)}   🔥 $streak day${streak == 1 ? '' : 's'}   ${_tierEmoji(tier)} ${tier.label}');
  if (bonusWordFound) {
    buffer.write('✨ Bonus word found!');
  }
  return buffer.toString().trim();
}
