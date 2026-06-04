import 'package:flutter/services.dart';

import '../models/app_entry.dart';

class AppService {
  AppService._();

  static const _channel = MethodChannel('searchit/apps');

  /// Registers a callback invoked when another app is installed, updated, or
  /// uninstalled. [action] is one of 'added', 'replaced', 'removed'.
  /// On 'replaced' the native side has already cleared that package's icon
  /// cache, so [getIcons] will regenerate a fresh icon.
  static void setOnPackageChanged(
      Future<void> Function(String package, String action)? callback) {
    if (callback == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPackageChanged') {
        final args = call.arguments as Map<dynamic, dynamic>;
        await callback(
          args['package'] as String,
          args['action'] as String,
        );
      }
    });
  }

  /// Phase 1: app metadata only (no icons) — very fast.
  static Future<List<AppEntry>> getAppsMetadata() async {
    final raw =
        await _channel.invokeMethod<List<dynamic>>('getAppsMetadata') ?? [];
    final apps = raw
        .map((e) => AppEntry.fromMap(e as Map<dynamic, dynamic>))
        .toList();
    apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return apps;
  }

  /// Phase 2: icon bytes for [packages], loaded in parallel on the native side.
  /// Returns a map of packageName → PNG bytes.
  static Future<Map<String, Uint8List>> getIcons(
      List<String> packages) async {
    if (packages.isEmpty) return {};
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'getIcons',
          {'packages': packages},
        ) ??
        {};
    return raw.map((k, v) => MapEntry(k as String, v as Uint8List));
  }

  static Future<bool> launch(String packageName) async {
    final ok = await _channel
        .invokeMethod<bool>('launchApp', {'package': packageName});
    return ok ?? false;
  }

  static Future<void> uninstall(String packageName) =>
      _channel.invokeMethod('uninstallApp', {'package': packageName});

  static Future<void> openAppInfo(String packageName) =>
      _channel.invokeMethod('openAppInfo', {'package': packageName});

  static Future<void> openPlayStore(String packageName) =>
      _channel.invokeMethod('openPlayStore', {'package': packageName});

  static Future<void> openHomeSettings() =>
      _channel.invokeMethod('openHomeSettings');
}
