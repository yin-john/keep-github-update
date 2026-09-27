/// Android 运行环境能力抽象：运行时权限、root / Shizuku 授权、APK 签名与包信息。
///
/// - GUI（Flutter）：由 MethodChannel 实现（见 platforms/flutter_android_env.dart）
/// - CLI/TUI（纯 Dart）：只能走 shell（root / Shizuku），见 [ShellAndroidEnv]
///
/// 所有方法在非 Android 平台都安全返回 false / null。
library;

import 'dart:io';

abstract class AndroidEnv {
  const AndroidEnv();

  /// 当前是否为 Android 平台
  bool get isAndroid => Platform.isAndroid;

  /// 是否有「所有文件访问」权限（Android 11+ 为 MANAGE_EXTERNAL_STORAGE）
  Future<bool> hasStoragePermission();

  /// 申请存储权限（会跳转系统设置页）
  Future<bool> requestStoragePermission();

  /// 是否有通知权限（Android 13+ 需要）
  Future<bool> hasNotificationPermission();

  /// 申请通知权限
  Future<bool> requestNotificationPermission();

  /// 是否已获得 root
  Future<bool> hasRoot();

  /// 主动申请 root（触发 su 授权弹窗）
  Future<bool> requestRoot();

  /// Shizuku 是否可用（已授权且命令可用）
  Future<bool> hasShizuku();

  /// 申请 Shizuku 授权
  Future<bool> requestShizuku();

  /// 读取 APK 文件的签名摘要（SHA-256 十六进制），读不到返回 null
  Future<String?> apkSignature(String path);

  /// 读取 APK 文件的包名，读不到返回 null
  Future<String?> apkPackageName(String path);

  /// 已安装应用的签名摘要，读不到返回 null
  Future<String?> installedSignature(String packageName);

  /// 已安装应用的 versionName，读不到返回 null
  Future<String?> installedAppVersion(String packageName);

  /// 用系统安装器安装 APK（普通安装，需用户手动确认）
  Future<bool> installWithSystem(String path);

  /// 应用内部可写目录（Android：/data/user/0/<包名>/files）
  Future<String?> appFilesDir();

  /// 应用专属外部目录（Android：/storage/emulated/0/Android/data/<包名>/files）
  Future<String?> appExternalFilesDir();
}

/// 纯 shell 实现：仅 root / Shizuku 相关能力可用（不需要 Flutter）。
class ShellAndroidEnv extends AndroidEnv {
  const ShellAndroidEnv();

  @override
  Future<bool> hasStoragePermission() async => false;

  @override
  Future<bool> requestStoragePermission() async => false;

  @override
  Future<bool> hasNotificationPermission() async => false;

  @override
  Future<bool> requestNotificationPermission() async => false;

  @override
  Future<bool> hasRoot() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await Process.run('su', ['-c', 'id']);
      return r.exitCode == 0 && (r.stdout as String).contains('uid=0');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestRoot() => hasRoot();

  @override
  Future<bool> hasShizuku() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await Process.run('shizuku', ['-v']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestShizuku() => hasShizuku();

  @override
  Future<String?> apkSignature(String path) async => null;

  @override
  Future<String?> apkPackageName(String path) async => null;

  @override
  Future<String?> installedSignature(String packageName) async => null;

  @override
  Future<String?> installedAppVersion(String packageName) async {
    if (!Platform.isAndroid) return null;
    final out = await _shell('dumpsys package $packageName');
    final m = RegExp(r'^\s*versionName=(\S+)', multiLine: true).firstMatch(out);
    return m?.group(1);
  }

  @override
  Future<bool> installWithSystem(String path) async => false;

  @override
  Future<String?> appFilesDir() async => null;

  @override
  Future<String?> appExternalFilesDir() async => null;

  Future<String> _shell(String cmd) async {
    for (final c in [
      ['su', '-c'],
      ['shizuku', '-c'],
      ['sh', '-c'],
    ]) {
      try {
        final r = await Process.run(c.first, [...c.sublist(1), cmd]);
        final out = (r.stdout as String?) ?? '';
        if (r.exitCode == 0 && out.trim().isNotEmpty) return out;
      } catch (_) {
        // 换下一种方式
      }
    }
    return '';
  }
}
