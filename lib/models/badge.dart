/// Day badge logic.
///
/// Acquisition: any 7 consecutive calendar days all have at least one launch.
/// Loss: last launch was 7 or more calendar days ago (or no launches at all).
class BadgeService {
  BadgeService._();

  /// Returns true if [launches] contains a streak of 7 consecutive calendar days.
  static bool hasEarned(List<DateTime> launches) {
    if (launches.length < 7) return false;

    final days = launches
        .map((l) => DateTime(l.year, l.month, l.day))
        .toSet()
        .toList()
      ..sort();

    var streak = 1;
    for (var i = 1; i < days.length; i++) {
      if (days[i].difference(days[i - 1]).inDays == 1) {
        streak++;
        if (streak >= 7) return true;
      } else {
        streak = 1;
      }
    }
    return false;
  }

  /// Returns true if the badge should be revoked:
  /// last launch was 7+ calendar days ago, or there are no launches.
  static bool shouldRevoke(List<DateTime> launches) {
    if (launches.isEmpty) return true;
    final last = launches.reduce((a, b) => a.isAfter(b) ? a : b);
    final today = DateTime.now();
    final daysSince = DateTime(today.year, today.month, today.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    return daysSince >= 7;
  }
}
