// Everything about "today" for the Daily Estate Challenge is derived from
// UTC, not the device's local timezone -- otherwise a player could get a
// fresh puzzle early (or repeat one) just by changing their device's
// timezone, and players in different timezones could see different
// puzzles at the same real-world moment.

int dailySeedForDate(DateTime date) {
  final utc = date.toUtc();
  return utc.year * 10000 + utc.month * 100 + utc.day;
}

String dailyDateKey(DateTime date) {
  final utc = date.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
}

// True if `previousDateKey` (from dailyDateKey) is the calendar day
// immediately before `date` (in UTC) -- used to decide whether playing
// today continues a streak or resets it.
bool isConsecutiveDay(String? previousDateKey, DateTime date) {
  if (previousDateKey == null) return false;
  final yesterday = date.toUtc().subtract(const Duration(days: 1));
  return previousDateKey == dailyDateKey(yesterday);
}
