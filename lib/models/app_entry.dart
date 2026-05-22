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

  // --- Search index, computed once per app so the engine never recomputes
  // these forms on every keystroke. See [Korean] for what each form means.

  /// [label] in canonical comparison form (lowercased, spaces stripped).
  final String labelNorm;

  /// [packageName] in canonical comparison form.
  final String packageNorm;

  /// Leading-consonant (초성) skeleton of [label].
  final String chosung;

  /// Revised-romanization of [label].
  final String roman;

  /// Coarse phonetic skeleton of [label] for fuzzy English ↔ Korean search.
  final String phonetic;

  /// [label] projected onto QWERTY keys — recovers wrong-IME typing.
  final String qwerty;

  /// Initials of an English [label] (e.g. "Google Play" → "gp").
  final String initials;

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
