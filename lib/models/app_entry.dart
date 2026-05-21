import 'dart:typed_data';

/// A single launchable app installed on the device.
class AppEntry {
  AppEntry({
    required this.label,
    required this.packageName,
    required this.firstInstallTime,
    required this.isSystem,
    required this.icon,
  });

  /// Human-readable app name (e.g. "카카오톡").
  final String label;

  /// Android package name (e.g. "com.kakao.talk").
  final String packageName;

  /// When the app was first installed — used for the 'new' badge.
  final DateTime firstInstallTime;

  /// System (pre-installed) apps cannot be uninstalled.
  final bool isSystem;

  /// Pre-rendered PNG icon bytes supplied by the platform channel.
  final Uint8List icon;

  /// True when the app was first installed within the last 7 days.
  bool get isNew =>
      DateTime.now().difference(firstInstallTime) < const Duration(days: 7);

  factory AppEntry.fromMap(Map<dynamic, dynamic> map) {
    return AppEntry(
      label: map['label'] as String,
      packageName: map['package'] as String,
      firstInstallTime:
          DateTime.fromMillisecondsSinceEpoch(map['firstInstallTime'] as int),
      isSystem: map['system'] as bool,
      icon: map['icon'] as Uint8List,
    );
  }
}
