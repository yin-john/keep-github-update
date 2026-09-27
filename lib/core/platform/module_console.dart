/// 模块刷入的「终端」输出通道。
///
/// [PlatformBridge.flashModule]（bridge.dart）在刷入 Magisk/KernelSU 模块时，
/// 把安装器的每行输出推送到这里：
/// - GUI 的「模块安装终端窗口」订阅 [stream] 实时显示；
/// - 没有窗口打开时输出仅写入日志文件（bridge 内部同时走 AppLog）。
library;

import 'dart:async';

class ModuleInstallConsole {
  ModuleInstallConsole._();

  static final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// 订阅安装输出（终端窗口）
  static Stream<String> get stream => _controller.stream;

  /// 推送一行输出（广播：无订阅者时安全丢弃）
  static void emit(String line) {
    final t = line.trimRight();
    if (t.isEmpty) return;
    _controller.add(t);
  }
}
