/// 简单的文件日志：由配置开关控制。
///
/// 路径优先放在用户可访问的位置（Android 为 <外部存储>/grku/logs/app.log），
/// 无写入权限时自动回退到应用私有目录，避免 Android 上因私有路径无法查看日志。
///
/// 只写文件（不写 stdout），以免污染 TUI 界面渲染。
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import '../config/app_paths.dart';

class AppLog {
  AppLog._();

  /// 是否启用（由配置决定）
  static bool enabled = false;

  /// 首选日志文件路径（用户可访问）
  static String primaryLogFilePath = p.join(defaultLogDir(), 'app.log');

  /// 回退日志文件路径（应用私有，始终可写）
  static String fallbackLogFilePath = p.join(fallbackLogDir(), 'app.log');

  /// 当前实际使用的日志文件路径
  static String logFilePath = primaryLogFilePath;

  /// 依据配置同步开关
  static void configure(bool on) {
    enabled = on;
  }

  /// 重新计算日志路径（Android 解析出应用目录后调用）
  static void refreshPaths() {
    primaryLogFilePath = p.join(defaultLogDir(), 'app.log');
    fallbackLogFilePath = p.join(fallbackLogDir(), 'app.log');
    logFilePath = primaryLogFilePath;
  }

  static void write(String level, String message) {
    if (!enabled) return;
    final line = '${DateTime.now().toIso8601String()} [$level] $message';
    if (_append(logFilePath, line)) return;
    // 首选路径不可写（如 Android 未授予存储权限）→ 回退到应用私有目录
    if (logFilePath != fallbackLogFilePath &&
        _append(fallbackLogFilePath, line)) {
      logFilePath = fallbackLogFilePath;
    }
  }

  static bool _append(String path, String line) {
    try {
      final f = File(path);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static void info(String message) => write('INFO', message);
  static void warn(String message) => write('WARN', message);
  static void error(String message) => write('ERROR', message);

  /// 清空日志文件
  static void clear() {
    try {
      final f = File(logFilePath);
      if (f.existsSync()) f.writeAsStringSync('');
    } catch (_) {}
  }
}
