import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../services/app_service.dart';

/// Font size of the app name in a grid tile.
const double _kNameFontSize = 12;

/// Line-height multiplier of the app name.
const double _kNameLineHeight = 1.1;

/// Height reserved for the app name: always two lines, so a single-line name
/// occupies the same vertical space as a two-line one and every tile in a
/// row keeps its icon at the same height.
const double _kNameHeight = _kNameFontSize * _kNameLineHeight * 2;

/// A single grid cell: app icon above its name, with a 'new' badge for
/// recently installed apps.
class AppTile extends StatelessWidget {
  const AppTile({super.key, required this.app, required this.onTap});

  final AppEntry app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: () => showAppActions(context, app),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Image.memory(app.icon, width: 52, height: 52),
                if (app.isNew)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.shade400,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Text(
                        'new',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: _kNameHeight,
              child: Text(
                app.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: _kNameFontSize,
                  height: _kNameLineHeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the long-press action popup: Delete, App info, Play Store.
/// Delete is disabled for system apps, which cannot be uninstalled.
Future<void> showAppActions(BuildContext context, AppEntry app) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Image.memory(app.icon, width: 36, height: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      app.label,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              enabled: !app.isSystem,
              subtitle: app.isSystem
                  ? const Text('시스템 앱은 삭제할 수 없습니다')
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                AppService.uninstall(app.packageName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App info'),
              onTap: () {
                Navigator.pop(sheetContext);
                AppService.openAppInfo(app.packageName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shop_outlined),
              title: const Text('Play Store'),
              onTap: () {
                Navigator.pop(sheetContext);
                AppService.openPlayStore(app.packageName);
              },
            ),
          ],
        ),
      );
    },
  );
}
