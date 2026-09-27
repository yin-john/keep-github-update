/// 从本地已下载的 APK 提取软件名称、包名、版本与图标（Android）。
///
/// 产物约定（放在该仓库的下载目录里，用户可直接查看）：
/// - 图标：`<dir>/app_icon.png`
/// - 信息：`<dir>/app_name.txt`（名称 / 包名 / 版本，每行一项）
///
/// 提取优先级：
/// 1. 显式给定 [apkPath]（刚下载完成）→ 直接提取并覆盖上述两个文件；
/// 2. 目录里已存在两个产物文件且比目录里最新的 APK 新 → 直接复用，不重复提取；
/// 3. 目录里存在 `*.apk` → 用**最新**的一个提取并覆盖两个文件；
/// 4. 目录不存在 / 没有 APK / 提取失败 → 返回 null。
///
/// 另提供 [extractInstalledAppInfoIntoDir]：未下载过 APK 时，
/// 从设备上**已安装的应用**提取同样的信息并写入同一组产物文件。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'android_env.dart';
import 'apk_info.dart';

/// 图标文件名（仓库下载目录下）
const String apkIconFileName = 'app_icon.png';

/// 信息文件名（仓库下载目录下）
const String apkNameFileName = 'app_name.txt';

/// 目录中最新的 APK 文件路径；没有则返回 null
String? newestApkInDir(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return null;
  File? best;
  DateTime? bestTime;
  for (final e in d.listSync()) {
    if (e is! File) continue;
    if (!e.path.toLowerCase().endsWith('.apk')) continue;
    final t = e.lastModifiedSync();
    if (best == null || bestTime == null || t.isAfter(bestTime)) {
      best = e;
      bestTime = t;
    }
  }
  return best?.path;
}

/// 把提取到的信息写成可读文本（每行一项，便于人工查看也可解析回来）
String formatApkInfoTxt(ApkAppInfo info) {
  final b = StringBuffer();
  if (info.label?.isNotEmpty ?? false) b.writeln('名称: ${info.label}');
  if (info.packageName?.isNotEmpty ?? false) {
    b.writeln('包名: ${info.packageName}');
  }
  if (info.version?.isNotEmpty ?? false) b.writeln('版本: ${info.version}');
  if (info.xposed) b.writeln('Xposed 模块: 是');
  return b.toString();
}

/// 解析信息文本；兼容旧格式（首行即名称，没有「名称:」前缀）
ApkAppInfo parseApkInfoTxt(String content, {String? iconPath}) {
  String? label;
  String? pkg;
  String? ver;
  var xposed = false;
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('名称:')) {
      label = line.substring(3).trim();
    } else if (line.startsWith('包名:')) {
      pkg = line.substring(3).trim();
    } else if (line.startsWith('版本:')) {
      ver = line.substring(3).trim();
    } else if (line.startsWith('Xposed 模块:')) {
      xposed = line.substring('Xposed 模块:'.length).trim() == '是';
    } else if (label == null) {
      label = line; // 旧格式：第一行就是名称
    }
  }
  String? clean(String? v) => (v == null || v.isEmpty) ? null : v;
  return ApkAppInfo(
    label: clean(label),
    packageName: clean(pkg),
    version: clean(ver),
    iconPath: iconPath,
    xposed: xposed,
  );
}

/// 按「提取优先级」获取名称 / 包名 / 版本 / 图标。
///
/// 返回的 [ApkAppInfo.iconPath] 指向 `<dir>/app_icon.png`（可能为 null）。
Future<ApkAppInfo?> extractApkInfoIntoDir(
  AndroidEnv env,
  String dir, {
  String? apkPath,
}) async {
  final d = Directory(dir);
  if (!d.existsSync()) return null;

  final apk = apkPath ?? newestApkInDir(dir);
  if (apk == null || !File(apk).existsSync()) return null;

  final nameFile = File(p.join(d.path, apkNameFileName));
  final iconFile = File(p.join(d.path, apkIconFileName));

  // 不是刚下载完（未显式指定 apkPath）时，命中缓存就直接复用，
  // 避免每次自动检测都重复提取
  if (apkPath == null) {
    final cached = _cachedResult(apk, nameFile, iconFile);
    if (cached != null) return cached;
  }

  try {
    final info = await env.apkAppInfo(apk);
    if (info.isEmpty) return null;
    return await _persistInfo(d, info);
  } catch (_) {
    // 提取失败（无权限 / 损坏的 APK 等）不影响其它流程
    return null;
  }
}

/// 从设备上**已安装的应用**提取名称/包名/版本/图标，并落盘到 [dir]
/// （图标 `app_icon.png`、信息 `app_name.txt`，与本地 APK 提取共用同一组产物）。
/// 目录不存在会自动创建；提取失败返回 null。
Future<ApkAppInfo?> extractInstalledAppInfoIntoDir(
  AndroidEnv env,
  String dir,
  String packageName,
) async {
  if (packageName.trim().isEmpty) return null;
  try {
    final info = await env.installedAppInfo(packageName.trim());
    if (info.isEmpty) return null;
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return await _persistInfo(d, info);
  } catch (_) {
    return null;
  }
}

/// 把提取到的信息落盘到目录：图标复制为 app_icon.png，
/// 名称/包名/版本写入 app_name.txt；两项皆无时返回 null
Future<ApkAppInfo?> _persistInfo(Directory d, ApkAppInfo info) async {
  final iconFile = File(p.join(d.path, apkIconFileName));
  final nameFile = File(p.join(d.path, apkNameFileName));

  // 原生提取的图标在应用私有目录，复制一份到下载目录（用户可见、可随目录保留）
  String? iconPath;
  if (info.iconPath != null && File(info.iconPath!).existsSync()) {
    await File(info.iconPath!).copy(iconFile.path);
    iconPath = iconFile.path;
  }
  final txt = formatApkInfoTxt(info);
  if (txt.trim().isNotEmpty) {
    await nameFile.writeAsString(txt);
  }
  if (iconPath == null && txt.trim().isEmpty) return null;
  return ApkAppInfo(
    label: info.label,
    packageName: info.packageName,
    version: info.version,
    iconPath: iconPath,
    xposed: info.xposed,
  );
}

/// 两个产物文件都存在且都比 APK 新时，视为有效缓存
ApkAppInfo? _cachedResult(String apk, File nameFile, File iconFile) {
  if (!nameFile.existsSync() || !iconFile.existsSync()) return null;
  final apkTime = File(apk).lastModifiedSync();
  if (nameFile.lastModifiedSync().isBefore(apkTime) ||
      iconFile.lastModifiedSync().isBefore(apkTime)) {
    return null; // APK 比缓存新（刚更新过），需要重新提取
  }
  return parseApkInfoTxt(nameFile.readAsStringSync(), iconPath: iconFile.path);
}
