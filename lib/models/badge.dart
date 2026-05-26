import 'app_entry.dart';

/// Badge assigned to an app based on its launch frequency.
/// Enum values are ordered by ascending priority so higher-index values
/// sort before lower-index ones (newApp=2 > day=1 > none=0).
enum AppBadge { none, day, newApp }

class BadgeService {
  BadgeService._();

  /// Returns the badge for [app] given its [launches] and whether the day badge
  /// was previously earned.
  ///
  /// Day badge acquisition: the 7 calendar days before today each have a launch.
  /// Day badge maintenance: once earned, badge persists while the last launch
  /// is within 7 calendar days of today; revoked at midnight after the 7th day.
  static AppBadge calculate(
    AppEntry app,
    List<DateTime> launches,
    bool dayBadgeEarned,
  ) {
    if (app.isNew) return AppBadge.newApp;
    if (launches.isEmpty) return AppBadge.none;

    final today = _dateOnly(DateTime.now());

    if (dayBadgeEarned) {
      final lastLaunch = launches.reduce((a, b) => a.isAfter(b) ? a : b);
      final daysSince = today.difference(_dateOnly(lastLaunch)).inDays;
      return daysSince < 7 ? AppBadge.day : AppBadge.none;
    }

    return _meetsAcquisition(launches, today) ? AppBadge.day : AppBadge.none;
  }

  /// Weighted launch score: each launch contributes 1 / (1 + fractional days ago).
  static double weightedScore(List<DateTime> launches) {
    if (launches.isEmpty) return 0.0;
    final now = DateTime.now();
    return launches.fold(0.0, (sum, l) {
      final daysAgo =
          now.difference(l).inMicroseconds / Duration.microsecondsPerDay;
      return sum + 1.0 / (1.0 + daysAgo);
    });
  }

  /// Acquisition: D-1 through D-7 each have at least one launch.
  static bool _meetsAcquisition(List<DateTime> launches, DateTime today) {
    for (var i = 1; i <= 7; i++) {
      if (!_hasLaunchOn(launches, today.subtract(Duration(days: i)))) {
        return false;
      }
    }
    return true;
  }

  static bool _hasLaunchOn(List<DateTime> launches, DateTime date) =>
      launches.any((l) =>
          l.year == date.year && l.month == date.month && l.day == date.day);

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
}
