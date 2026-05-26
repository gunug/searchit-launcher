import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_entry.dart';

/// One stored search keyword and the apps that were launched under it from
/// the similar / related sections.
class HistoryEntry {
  HistoryEntry({required this.keyword, required this.packages, required this.updatedAt});

  final String keyword;
  final List<String> packages;
  final int updatedAt;

  Map<String, dynamic> toJson() =>
      {'keyword': keyword, 'packages': packages, 'updatedAt': updatedAt};

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        keyword: json['keyword'] as String,
        packages: (json['packages'] as List).cast<String>(),
        updatedAt: json['updatedAt'] as int,
      );
}

/// Persists the search history, recent-app list, and per-app launch timestamps.
/// All data is recorded only for launches through this launcher — no system
/// usage-stats permission is required.
class StorageService {
  StorageService._();

  static const _historyKey = 'search_history';
  static const _recentKey = 'recent_apps';
  static const _recentLimit = 30;
  static const _launchHistoryKey = 'launch_history_v2';
  static const _launchRetentionDays = 30;
  static const _dayBadgeEarnedKey = 'day_badge_earned';
  static const _appCacheKey = 'app_cache_v1';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  // --- Search history -------------------------------------------------------

  static Future<List<HistoryEntry>> loadHistory() async {
    final raw = (await _store).getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Records that [packageName] was launched from a similar/related result
  /// while [keyword] was the active query. Adds to the keyword's app list.
  static Future<void> recordHistory(String keyword, String packageName) async {
    keyword = keyword.trim();
    if (keyword.isEmpty) return;
    final entries = await loadHistory();
    final existing = entries.where((e) => e.keyword == keyword).firstOrNull;
    if (existing != null) {
      if (!existing.packages.contains(packageName)) {
        existing.packages.add(packageName);
      }
      entries
        ..remove(existing)
        ..add(HistoryEntry(
          keyword: keyword,
          packages: existing.packages,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
    } else {
      entries.add(HistoryEntry(
        keyword: keyword,
        packages: [packageName],
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    await (await _store).setString(
      _historyKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  // --- Recent apps ----------------------------------------------------------

  static Future<List<String>> loadRecents() async {
    return (await _store).getStringList(_recentKey) ?? [];
  }

  /// Moves [packageName] to the front of the recent-app list.
  static Future<void> recordLaunch(String packageName) async {
    final recents = await loadRecents()
      ..remove(packageName);
    recents.insert(0, packageName);
    if (recents.length > _recentLimit) {
      recents.removeRange(_recentLimit, recents.length);
    }
    await (await _store).setStringList(_recentKey, recents);
  }

  // --- Launch history (for badge calculation) ----------------------------------

  /// Returns a map of packageName → list of launch timestamps (ms since epoch).
  static Future<Map<String, List<int>>> loadLaunchHistory() async {
    final raw = (await _store).getString(_launchHistoryKey);
    if (raw == null || raw.isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as List).cast<int>()));
  }

  // --- Day badge earned set -------------------------------------------------

  static Future<Set<String>> loadDayBadgeEarned() async =>
      ((await _store).getStringList(_dayBadgeEarnedKey) ?? []).toSet();

  static Future<void> saveDayBadgeEarned(Set<String> earned) async =>
      (await _store).setStringList(_dayBadgeEarnedKey, earned.toList());

  // --- App metadata cache (no icons) ----------------------------------------

  /// Returns the last-saved app list metadata. Empty list on first launch.
  static Future<List<AppEntry>> loadCachedApps() async {
    final raw = (await _store).getString(_appCacheKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AppEntry.fromCacheJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Saves app metadata to cache (icons are excluded).
  static Future<void> saveCachedApps(List<AppEntry> apps) async =>
      (await _store).setString(
        _appCacheKey,
        jsonEncode(apps.map((a) => a.toCacheJson()).toList()),
      );

  // --- Launch timestamps ----------------------------------------------------

  /// Appends the current timestamp for [packageName] and prunes entries older
  /// than [_launchRetentionDays] so storage does not grow unboundedly.
  static Future<void> recordLaunchTimestamp(String packageName) async {
    final history = await loadLaunchHistory();
    final now = DateTime.now();
    final cutoff = now
        .subtract(const Duration(days: _launchRetentionDays))
        .millisecondsSinceEpoch;
    final launches = (history[packageName] ?? [])
      ..removeWhere((ts) => ts < cutoff)
      ..add(now.millisecondsSinceEpoch);
    history[packageName] = launches;
    await (await _store).setString(
      _launchHistoryKey,
      jsonEncode(history),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
