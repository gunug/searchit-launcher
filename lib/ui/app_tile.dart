import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/app_entry.dart';
import '../services/app_service.dart';

Widget _iconWidget(Uint8List? icon, double size) {
  if (icon != null) return Image.memory(icon, width: size, height: size);
  return SizedBox(
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
    ),
  );
}

/// Font size of the app name in a grid tile.
const double _kNameFontSize = 12;

/// Line-height multiplier of the app name.
const double _kNameLineHeight = 1.1;

/// Height reserved for the app name: always two lines.
const double _kNameHeight = _kNameFontSize * _kNameLineHeight * 2;

/// A single grid cell: app icon above its name, with optional badges.
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.app,
    required this.onTap,
    this.showDayBadge = false,
    this.showNewBadge = false,
    this.showLockBadge = false,
    this.isLocked = false,
    this.onClearRecord,
    this.onToggleLock,
  });

  final AppEntry app;
  final VoidCallback onTap;
  final bool showDayBadge;
  final bool showNewBadge;
  final bool showLockBadge;
  final bool isLocked;
  final VoidCallback? onClearRecord;
  final VoidCallback? onToggleLock;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: () => showAppActions(
        context,
        app,
        isLocked: isLocked,
        onToggleLock: onToggleLock,
        onClearRecord: onClearRecord,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _iconWidget(app.icon, 52),
                if (showLockBadge)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: _lockBadge(),
                  )
                else if (showNewBadge)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: _badge('new', Colors.greenAccent.shade400),
                  )
                else if (showDayBadge)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: _badge('day', Colors.amber.shade400),
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

Widget _badge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

Widget _lockBadge() => Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.blueAccent.shade200,
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.lock, size: 10, color: Colors.white),
    );

/// Shows the long-press action popup.
Future<void> showAppActions(
  BuildContext context,
  AppEntry app, {
  bool isLocked = false,
  VoidCallback? onToggleLock,
  VoidCallback? onClearRecord,
}) {
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
                  _iconWidget(app.icon, 36),
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
              leading: Icon(isLocked ? Icons.lock_open : Icons.lock_outline),
              title: Text(isLocked ? '잠금 해제 / Unlock' : '잠금 / Lock'),
              onTap: () {
                Navigator.pop(sheetContext);
                onToggleLock?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_toggle_off),
              title: const Text('기록 삭제 / Clear History'),
              onTap: () {
                Navigator.pop(sheetContext);
                onClearRecord?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('삭제 / Delete'),
              enabled: !app.isSystem,
              subtitle: app.isSystem
                  ? const Text('시스템 앱은 삭제할 수 없습니다\nSystem apps cannot be uninstalled')
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                try {
                  await AppService.uninstall(app.packageName);
                } on Exception catch (e) {
                  if (context.mounted) {
                    _showErrorDialog(context, e.toString());
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('앱 정보 / App Info'),
              onTap: () {
                Navigator.pop(sheetContext);
                AppService.openAppInfo(app.packageName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shop_outlined),
              title: const Text('스토어 / Play Store'),
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

void _showErrorDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        var copied = false;
        return AlertDialog(
          title: const Text('삭제 실패 / Delete Failed'),
          content: SingleChildScrollView(child: SelectableText(message)),
          actions: [
            TextButton.icon(
              icon: Icon(copied ? Icons.check : Icons.copy, size: 18),
              label: Text(copied ? '복사됨 / Copied' : '복사 / Copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message));
                setState(() => copied = true);
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기 / Close'),
            ),
          ],
        );
      },
    ),
  );
}
