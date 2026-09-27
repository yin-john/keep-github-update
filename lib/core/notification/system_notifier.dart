/// 系统通知抽象与控制台实现（CLI/TUI 使用，经平台桥接弹原生通知）
library;

import '../config/models.dart';
import '../platform/bridge.dart';

abstract class SystemNotifier {
  Future<void> show(String title, String body, NotificationLevel level);
}

/// 控制台/CLI/TUI 通知：先打印，再尝试 OS 原生通知
class ConsoleSystemNotifier implements SystemNotifier {
  const ConsoleSystemNotifier(this.bridge);
  final PlatformBridge bridge;

  @override
  Future<void> show(String title, String body, NotificationLevel level) async {
    print('[${level.name}] $title — $body');
    await bridge.notifySystem(title, body, level);
  }
}
