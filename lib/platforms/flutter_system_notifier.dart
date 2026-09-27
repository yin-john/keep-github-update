/// GUI 系统通知实现。
/// - Android / Linux：使用 flutter_local_notifications（该插件 17.x 不支持 Windows）。
/// - Windows：降级为 PowerShell Toast（因插件无 Windows 原生实现）。
library;

import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/config/models.dart';
import '../core/notification/system_notifier.dart';

class FlutterSystemNotifier implements SystemNotifier {
  const FlutterSystemNotifier(this.plugin);
  final FlutterLocalNotificationsPlugin plugin;

  static Future<FlutterSystemNotifier> init() async {
    final plugin = FlutterLocalNotificationsPlugin();
    if (!Platform.isWindows) {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const linux = LinuxInitializationSettings(defaultActionName: 'grku');
      await plugin.initialize(const InitializationSettings(
        android: android,
        linux: linux,
      ));
    }
    if (Platform.isAndroid) {
      // Android 13+ 需运行时申请通知权限，否则通知会被静默丢弃
      try {
        await plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } catch (_) {
        // 用户拒绝或系统不支持时忽略
      }
    }
    return FlutterSystemNotifier(plugin);
  }

  @override
  Future<void> show(String title, String body, NotificationLevel level) async {
    if (Platform.isWindows) {
      await _showWindowsToast(title, body);
      return;
    }
    const android = AndroidNotificationDetails(
      'grku_updates',
      'grku 更新',
      importance: Importance.max,
      priority: Priority.high,
    );
    const linux = LinuxNotificationDetails();
    await plugin.show(
      0,
      title,
      body,
      const NotificationDetails(android: android, linux: linux),
    );
  }

  Future<void> _showWindowsToast(String title, String body) async {
    const script = r'''
$ErrorActionPreference='SilentlyContinue'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
$t = [System.Environment]::GetEnvironmentVariable('GRKU_T')
$b = [System.Environment]::GetEnvironmentVariable('GRKU_B')
$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$texts = $template.GetElementsByTagName('text')
$texts.Item(0).AppendChild($template.CreateTextNode($t)) | Out-Null
$texts.Item(1).AppendChild($template.CreateTextNode($b)) | Out-Null
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('grku').Show($template)
''';
    try {
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        environment: {'GRKU_T': title, 'GRKU_B': body},
      );
      if (r.exitCode != 0) print('[$title] $body');
    } catch (_) {
      print('[$title] $body');
    }
  }
}
