import 'dart:typed_data';

import '../search/korean.dart';

/// A single launchable app installed on the device.
class AppEntry {
  AppEntry({
    required this.label,
    required this.packageName,
    required this.firstInstallTime,
    required this.isSystem,
    required this.icon,
  })  : labelNorm = Korean.normalize(label),
        packageNorm = Korean.normalize(packageName),
        chosung = Korean.chosung(label),
        roman = Korean.romanize(label),
        phonetic = Korean.phoneticKey(label),
        qwerty = Korean.qwerty(label),
        initials = Korean.initials(label);

  final String label;
  final String packageName;
  final DateTime firstInstallTime;
  final bool isSystem;

  /// PNG icon bytes. Null until icons are loaded (shows placeholder in UI).
  final Uint8List? icon;

  final String labelNorm;
  final String packageNorm;
  final String chosung;
  final String roman;
  final String phonetic;
  final String qwerty;
  final String initials;

  bool get isNew =>
      DateTime.now().difference(firstInstallTime) < const Duration(days: 7);

  /// Returns a copy with [icon] replaced.
  AppEntry copyWithIcon(Uint8List? icon) => AppEntry(
        label: label,
        packageName: packageName,
        firstInstallTime: firstInstallTime,
        isSystem: isSystem,
        icon: icon,
      );

  /// Constructs from the native platform channel map (includes icon bytes).
  factory AppEntry.fromMap(Map<dynamic, dynamic> map) => AppEntry(
        label: map['label'] as String,
        packageName: map['package'] as String,
        firstInstallTime:
            DateTime.fromMillisecondsSinceEpoch(map['firstInstallTime'] as int),
        isSystem: map['system'] as bool,
        icon: map['icon'] as Uint8List?,
      );

  /// Constructs from the local metadata cache (no icon).
  factory AppEntry.fromCacheJson(Map<String, dynamic> json) => AppEntry(
        label: json['label'] as String,
        packageName: json['package'] as String,
        firstInstallTime:
            DateTime.fromMillisecondsSinceEpoch(json['firstInstallTime'] as int),
        isSystem: json['system'] as bool,
        icon: null,
      );

  /// Serialises metadata only (no icon) for the local cache.
  Map<String, dynamic> toCacheJson() => {
        'label': label,
        'package': packageName,
        'firstInstallTime': firstInstallTime.millisecondsSinceEpoch,
        'system': isSystem,
      };
}
