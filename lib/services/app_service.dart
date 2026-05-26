import 'package:flutter/services.dart';

import '../models/app_entry.dart';

/// Bridges the Flutter launcher to the native [MethodChannel] that knows how
/// to enumerate, launch and manage installed apps.
class AppService {
  AppService._();

  static const _channel = MethodChannel('searchit/apps');

  /// Loads every launchable app on the device (system apps included).
  static Future<List<AppEntry>> getApps() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('getApps') ?? [];
    final apps = raw
        .map((e) => AppEntry.fromMap(e as Map<dynamic, dynamic>))
        .toList();
    apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return apps;
  }

  /// Launches [packageName]; returns false when no launch intent exists.
  static Future<bool> launch(String packageName) async {
    final ok = await _channel
        .invokeMethod<bool>('launchApp', {'package': packageName});
    return ok ?? false;
  }

  /// Fires the system uninstall dialog for [packageName].
  static Future<void> uninstall(String packageName) {
    return _channel.invokeMethod('uninstallApp', {'package': packageName});
  }

  /// Opens the system "App info" screen for [packageName].
  static Future<void> openAppInfo(String packageName) {
    return _channel.invokeMethod('openAppInfo', {'package': packageName});
  }

  /// Opens the Play Store page for [packageName].
  static Future<void> openPlayStore(String packageName) {
    return _channel.invokeMethod('openPlayStore', {'package': packageName});
  }

  /// Opens the Android system "Default apps → Home app" settings screen.
  static Future<void> openHomeSettings() {
    return _channel.invokeMethod('openHomeSettings');
  }
}
