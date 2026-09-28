/// 应用数据目录与默认路径。
///
/// - Windows: %APPDATA%\github_releases_keep_update
/// - Linux:   $XDG_CONFIG_HOME/github_releases_keep_update 或 ~/.config/...
/// - Android: 由 main 在启动时通过系统 API 解析出可写目录（见 [setAppBaseDir]）；
///            默认下载目录位于公共存储（需「所有文件访问」权限）。
library;

import 'dart:io';
import 'package:path/path.dart' as p;

/// 应用数据目录名（与应用/可执行文件同名）
const String appDirName = 'github_releases_keep_update';

/// Android 包名（需与 android/app/build.gradle.kts 的 applicationId 一致）
const String androidPackageId = 'com.example.github_releases_keep_update';

/// Android 启动时解析出的可写根目录（内部存储 files 目录）
String? _appBaseOverride;

/// Android 启动时探测并决定的配置文件路径（见 [resolveAndroidConfigPath]）
String? _configPathOverride;

/// 设置 Android 应用可写根目录（由 main 在启动时调用）
void setAppBaseDir(String dir) {
  if (dir.isNotEmpty) _appBaseOverride = dir;
}

/// 设置 Android 配置文件路径（由 main 在启动时探测可写性后调用）
void setConfigPathOverride(String path) {
  if (path.isNotEmpty) _configPathOverride = path;
}

/// 测试用：清空覆盖值
void resetAppBaseDir() {
  _appBaseOverride = null;
  _configPathOverride = null;
}

/// Android 公共存储根目录
String androidExternalRoot() {
  final ext = Platform.environment['EXTERNAL_STORAGE'];
  if (ext != null && ext.isNotEmpty) return ext;
  return '/storage/emulated/0';
}

/// Android 公共存储下的应用根目录（logs/ 与配置文件同在此处）
String androidPublicRoot() => p.join(androidExternalRoot(), 'grku');

/// Android 应用私有目录（无需任何存储权限即可读写）
String androidPrivateRoot() {
  final override = _appBaseOverride;
  if (override != null && override.isNotEmpty) return override;
  return p.join(
      androidExternalRoot(), 'Android', 'data', androidPackageId, 'files');
}

/// 应用数据根目录
String appDataDir() {
  if (Platform.isAndroid) return p.join(androidPrivateRoot(), appDirName);
  final env = Platform.environment;
  if (Platform.isWindows) {
    final appData = env['APPDATA'];
    final base = (appData != null && appData.isNotEmpty)
        ? appData
        : (env['USERPROFILE'] ?? Directory.current.path);
    return p.join(base, appDirName);
  }
  if (Platform.isLinux) {
    final xdg = env['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) return p.join(xdg, appDirName);
    return p.join(env['HOME'] ?? Directory.current.path, '.config', appDirName);
  }
  final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.current.path;
  return p.join(home, appDirName);
}

/// 默认配置文件路径（可用环境变量 GRKU_CONFIG 覆盖）
/// - Android：公共存储 <外部存储>/grku/config.yaml（与 logs/ 同一父目录，
///   启动时探测可写性，不可写时由 [resolveAndroidConfigPath] 回退私有目录）
/// - 其它平台：应用数据目录下的 config.yaml
String defaultConfigPath() {
  final env = Platform.environment;
  final override = env['GRKU_CONFIG'];
  if (override != null && override.isNotEmpty) return override;
  if (Platform.isAndroid) {
    final decided = _configPathOverride;
    if (decided != null && decided.isNotEmpty) return decided;
    return p.join(androidPublicRoot(), 'config.yaml');
  }
  return p.join(appDataDir(), 'config.yaml');
}

/// Android 无存储权限时的回退配置路径（应用私有，始终可读写）
String fallbackConfigPath() {
  if (Platform.isAndroid) {
    return p.join(androidPrivateRoot(), appDirName, 'config.yaml');
  }
  return defaultConfigPath();
}

/// Android 启动时决定配置文件位置：
/// 公共存储（[publicRoot]，与 logs/ 同一父目录）可写 → 把私有目录里的
/// 旧配置（config.yaml / repos.yaml / config.yaml.bak）复制过去（不删除
/// 私有副本，作为权限撤销后的兜底）并返回公共路径；不可写 → 返回私有路径
/// [privateConfigPath]。
String resolveAndroidConfigPath({
  required String publicRoot,
  required String privateConfigPath,
}) {
  final publicDir = Directory(publicRoot);
  try {
    if (!publicDir.existsSync()) publicDir.createSync(recursive: true);
    final probe = File(p.join(publicRoot, '.grku_probe'));
    probe.writeAsStringSync('ok', flush: true);
    probe.deleteSync();
  } catch (_) {
    return privateConfigPath; // 公共存储不可写（无「所有文件访问」权限）
  }
  final publicCfg = p.join(publicRoot, 'config.yaml');
  if (!File(publicCfg).existsSync()) {
    final srcDir = File(privateConfigPath).parent;
    if (srcDir.existsSync()) {
      for (final name in const ['config.yaml', 'repos.yaml', 'config.yaml.bak']) {
        try {
          final src = File(p.join(srcDir.path, name));
          if (src.existsSync()) {
            final dst = File(p.join(publicRoot, name));
            if (!dst.existsSync()) src.copySync(dst.path);
          }
        } catch (_) {
          // 单个文件迁移失败不影响其余文件
        }
      }
    }
  }
  return publicCfg;
}

/// 默认下载目录：
/// - Android：公共存储 <外部存储>/grku/downloads（需「所有文件访问」权限，便于导出/共享）
/// - 其它平台：应用数据目录下的 downloads/
String defaultDownloadDir() {
  if (Platform.isAndroid) {
    return p.join(androidExternalRoot(), 'grku', 'downloads');
  }
  return p.join(appDataDir(), 'downloads');
}

/// 无存储权限时的回退下载目录（Android 应用私有，始终可读写）
String fallbackDownloadDir() {
  if (Platform.isAndroid) {
    return p.join(androidPrivateRoot(), appDirName, 'downloads');
  }
  return defaultDownloadDir();
}

/// 日志目录：
/// - Android：公共存储 <外部存储>/grku/logs（用户可直接查看，无需 root）
/// - 其它平台：应用数据目录下的 logs/
String defaultLogDir() {
  if (Platform.isAndroid) {
    return p.join(androidExternalRoot(), 'grku', 'logs');
  }
  return p.join(appDataDir(), 'logs');
}

/// 无存储权限时的回退日志目录（Android 应用私有）
String fallbackLogDir() {
  if (Platform.isAndroid) {
    return p.join(androidPrivateRoot(), appDirName, 'logs');
  }
  return defaultLogDir();
}

/// 单个仓库的下载目录：<基准下载目录>/<作者名>@<repo名>
String repoDownloadDir(String owner, String repo, {String? baseDir}) =>
    p.join(baseDir ?? defaultDownloadDir(), '$owner@$repo');

/// 清空某个仓库的下载目录（删除该仓库对应的下载文件夹）
Future<void> clearRepoDownloads(String owner, String repo,
    {String? baseDir}) async {
  final dir = Directory(repoDownloadDir(owner, repo, baseDir: baseDir));
  if (await dir.exists()) await dir.delete(recursive: true);
}
