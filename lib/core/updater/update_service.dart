/// 更新编排服务：检测版本 → 匹配资产 → 下载 → 应用 → 派发通知/Webhook
library;

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../config/models.dart';
import '../config/app_paths.dart';
import '../log/app_log.dart';
import '../github/release_fetcher.dart';
import '../github/release_model.dart';
import '../mirror/mirror_resolver.dart';
import '../matcher/asset_matcher.dart';
import '../download/download_manager.dart';
import '../download/checksum.dart';
import '../notification/notification_dispatcher.dart';
import '../platform/android_env.dart';
import '../platform/bridge.dart';
import '../version/installed_version.dart';
import 'updater.dart';

typedef ProgressCallback = void Function(int received, int total);

/// 下载成功但安装/应用失败：已下载的文件仍在，可直接重试安装（无需重新下载）
class InstallFailedException implements Exception {

  InstallFailedException(this.message, this.localPath);
  final String message;

  /// 已下载文件的路径（重试安装时复用）
  final String localPath;

  @override
  String toString() => message;
}

class UpdateCheck {

  const UpdateCheck({
    required this.repo,
    required this.release,
    required this.match,
    required this.hasUpdate,
    this.installedVersion,
  });
  final RepoConfig repo;
  final Release release;
  final MatchResult? match;
  final bool hasUpdate;

  /// 设备上检测到的真实已装版本（Android 模块/应用、便携目录版本记录）；未知为 null
  final String? installedVersion;
}

/// 从设备反查出的仓库身份（用于自动补全包名 / 模块 ID）
class UpdateIdentity {
  const UpdateIdentity({this.packageName, this.moduleId});
  final String? packageName;
  final String? moduleId;
}

class UpdateService {

  UpdateService({
    required this.fetcher,
    required this.mirror,
    required this.matcher,
    required this.downloader,
    required this.updaters,
    required this.currentPlatform,
    this.notifications,
    this.deviceArch,
    this.device,
    this.androidEnv,
  });
  final ReleaseFetcher fetcher;
  final MirrorResolver mirror;
  final AssetMatcher matcher;
  final DownloadManager downloader;
  final List<Updater> updaters;
  final PlatformType currentPlatform;
  final NotificationDispatcher? notifications;
  final TargetArch? deviceArch; // 当前设备架构（仅 Android 有效），用于资产规则选择
  final PlatformBridge? device; // 用于读取设备上的已装版本（Android）
  final AndroidEnv? androidEnv; // GUI：通过系统 API 读取已装应用版本（无需 root）

  Map<String, String>? _modulesCache;
  Map<String, String>? _pkgVersionsCache;

  /// 检测单个仓库：返回是否有可更新版本
  Future<UpdateCheck> check(RepoConfig repo) async {
    final release = await fetcher.getLatest(repo.owner, repo.repo);
    final match =
        matcher.match(release, currentPlatform, repo.assetRules, deviceArch);
    // 以设备上真实安装的版本为准；读不到时退回配置里记录的 tag
    final installed = await resolveInstalledVersion(repo);
    final bool hasUpdate;
    if (match == null) {
      hasUpdate = false;
    } else if (installed != null && installed.isNotEmpty) {
      hasUpdate = !versionMatches(installed, release.tagName);
    } else {
      hasUpdate = repo.lastInstalledTag != release.tagName;
    }
    AppLog.info('检测 ${repo.fullName} → 已装 '
        '${installed ?? repo.lastInstalledTag ?? '未知'}，最新 ${release.tagName}'
        '${hasUpdate ? '（可更新）' : ''}');
    return UpdateCheck(
      repo: repo,
      release: release,
      match: match,
      hasUpdate: hasUpdate,
      installedVersion: installed,
    );
  }

  /// 列出仓库的全部 release（含预发布；「更多版本」页用）
  Future<List<Release>> listReleases(RepoConfig repo) =>
      fetcher.listReleases(repo.owner, repo.repo);

  /// 为指定 release 生成检测结果（资产匹配 + 构造 UpdateCheck），
  /// 供「更多版本」页手动下载安装指定版本
  Future<UpdateCheck> checkRelease(RepoConfig repo, Release release) async {
    final match =
        matcher.match(release, currentPlatform, repo.assetRules, deviceArch);
    return UpdateCheck(
      repo: repo,
      release: release,
      match: match,
      hasUpdate: true,
    );
  }

  Future<Map<String, String>> _modules() async {
    if (_modulesCache != null) return _modulesCache!;
    final r = device == null
        ? const <String, String>{}
        : await device!.androidModuleProps();
    return _modulesCache = r;
  }

  Future<Map<String, String>> _packageVersions() async {
    if (_pkgVersionsCache != null) return _pkgVersionsCache!;
    final r = device == null
        ? const <String, String>{}
        : await device!.androidPackageVersions();
    return _pkgVersionsCache = r;
  }

  /// 解析该仓库在设备上实际安装的版本：
  /// Android 模块 → module.prop 的 version/versionCode
  /// Android 应用 → 已装应用的 versionName（需配置 packageName 或可反查）
  /// 便携目录 → 安装目录下的版本记录文件
  /// 都读不到时回退到配置记录的 lastInstalledTag
  Future<String?> resolveInstalledVersion(RepoConfig repo) async {
    if (currentPlatform == PlatformType.android && device != null) {
      final hasModule =
          repo.assetRules.any((r) => r.strategy == UpdateStrategy.module);
      if (hasModule) {
        final modules = await _modules();
        final id = matchModuleId(modules,
            moduleId: repo.moduleId, owner: repo.owner, repo: repo.repo);
        if (id != null) {
          final prop = parseModuleProp(modules[id] ?? '');
          final v = prop.version.isNotEmpty ? prop.version : prop.versionCode;
          if (v.isNotEmpty) return v;
        }
      }
      final hasApk =
          repo.assetRules.any((r) => r.strategy == UpdateStrategy.apk);
      if (hasApk) {
        final configured = (repo.packageName != null &&
                repo.packageName!.isNotEmpty)
            ? repo.packageName
            : null;
        // 优先用系统 API 读取（无需 root）
        if (configured != null && androidEnv != null) {
          final v = await androidEnv!.installedAppVersion(configured);
          if (v != null && v.isNotEmpty) return v;
        }
        final versions = await _packageVersions();
        final pkg = configured ??
            guessPackageName(versions, installedTag: repo.lastInstalledTag);
        final v = pkg == null ? null : versions[pkg];
        if (v != null && v.isNotEmpty) return v;
      }
    }
    final dir = repo.installDir;
    if (dir != null && dir.isNotEmpty) {
      try {
        final f = File(versionFilePath(dir));
        if (await f.exists()) {
          final v = parseVersionFile(await f.readAsString());
          if (v != null) return v;
        }
      } catch (_) {
        // 忽略读取失败
      }
    }
    return repo.lastInstalledTag;
  }

  /// 依据设备上「已装版本 == tag」反查包名/模块 ID，用于自动补全配置
  Future<UpdateIdentity?> detectIdentity(RepoConfig repo, String tag) async {
    if (currentPlatform != PlatformType.android ||
        device == null ||
        tag.isEmpty) {
      return null;
    }
    if (repo.assetRules.any((r) => r.strategy == UpdateStrategy.module)) {
      final modules = await _modules();
      for (final e in modules.entries) {
        final prop = parseModuleProp(e.value);
        if (versionMatches(prop.version, tag) ||
            versionMatches(prop.versionCode, tag)) {
          return UpdateIdentity(moduleId: e.key);
        }
      }
      return null;
    }
    if (repo.assetRules.any((r) => r.strategy == UpdateStrategy.apk)) {
      final versions = await _packageVersions();
      final pkg = guessPackageName(versions,
          installedTag: tag, exclude: repo.packageName);
      if (pkg != null) return UpdateIdentity(packageName: pkg);
    }
    return null;
  }

  /// 批量检测
  Future<List<UpdateCheck>> checkAll(List<RepoConfig> repos) async {
    final results = <UpdateCheck>[];
    for (final r in repos) {
      try {
        results.add(await check(r));
      } catch (e) {
        results.add(UpdateCheck(
          repo: r,
          release: const Release(
              tagName: '',
              name: '',
              prerelease: false,
              htmlUrl: '',
              assets: []),
          match: null,
          hasUpdate: false,
        ));
        print('检测 ${r.fullName} 失败: $e');
      }
    }
    return results;
  }

  /// 执行更新：下载并应用；dryRun 仅下载不应用；[cancelToken] 可中断下载。
  ///
  /// [onDownloaded] 在**下载完成、安装之前**回调（dryRun 也会触发），
  /// 用于在安装前/安装失败时也能提取 APK 信息（名称/图标/包名/版本）。
  Future<File> update(
    UpdateCheck c, {
    String? downloadDir,
    ProgressCallback? onProgress,
    bool dryRun = false,
    CancelToken? cancelToken,
    Future<void> Function(File file)? onDownloaded,
  }) async {
    if (!c.hasUpdate || c.match == null) {
      throw Exception('没有可更新的内容');
    }
    final asset = c.match!.asset;
    final rule = c.match!.rule;
    final url = mirror.resolve(asset.browserDownloadUrl);
    // 每个仓库单独的下载目录：<基准目录>/<作者名>@<repo名>
    final dir = repoDownloadDir(c.repo.owner, c.repo.repo, baseDir: downloadDir);
    await Directory(dir).create(recursive: true);
    final savePath = p.join(dir, asset.name);

    // 若开启校验：先定位并读取 release 下的校验文件，解析出期望哈希
    String? expectedChecksum;
    if (rule.verifyChecksum) {
      final csAsset = findChecksumAsset(c.release, asset, rule);
      if (csAsset != null) {
        try {
          final csUrl = mirror.resolve(csAsset.browserDownloadUrl);
          final csText = await downloader.downloadText(csUrl);
          expectedChecksum = parseChecksum(csText, rule.checksumType);
          if (expectedChecksum == null) {
            print('未能从校验文件解析出 ${rule.checksumType.ext} 哈希，跳过校验');
          }
        } catch (e) {
          print('获取校验文件失败，跳过校验: $e');
        }
      } else {
        print('未找到 ${rule.checksumType.ext} 校验文件，跳过校验');
      }
    }

    await notifications?.dispatch(
        NotificationEvent.updateStarted, c.repo, c.release.tagName, currentPlatform);
    AppLog.info('开始更新 ${c.repo.fullName} → ${c.release.tagName}'
        '（资产 ${asset.name}，来源 $url）');
    try {
      final file = await downloader.download(url, savePath,
          onProgress: onProgress,
          expectedChecksum: expectedChecksum,
          checksumType: rule.checksumType,
          cancelToken: cancelToken);
      // 下载完成即回调（安装前）：回调内部自行兜底，不应影响后续安装
      if (onDownloaded != null) {
        try {
          await onDownloaded(file);
        } catch (e) {
          AppLog.warn('onDownloaded 回调失败（忽略）: $e');
        }
      }
      if (!dryRun) {
        if (cancelToken?.isCancelled ?? false) throw DownloadCancelled();
        final updater = updaters.firstWhere(
          (u) => u.isApplicable(currentPlatform, c.match!.rule.strategy),
          orElse: () =>
              throw Exception('无适用的更新器: ${c.match!.rule.strategy}'),
        );
        try {
          await updater.apply(
            asset: asset,
            localPath: file.path,
            repo: c.repo,
            rule: c.match!.rule,
          );
        } catch (e) {
          throw InstallFailedException('安装失败：$e', file.path);
        }
        // 在目标目录写入版本记录文件
        await _writeVersionFile(c.repo, c.release.tagName, asset, file);
      }
      await notifications?.dispatch(NotificationEvent.updateSuccess, c.repo,
          c.release.tagName, currentPlatform);
      AppLog.info('更新成功 ${c.repo.fullName} → ${c.release.tagName}'
          '${dryRun ? '（仅下载）' : ''}');
      return file;
    } catch (e) {
      AppLog.error('更新失败 ${c.repo.fullName}: $e');
      await notifications?.dispatch(NotificationEvent.updateFailed, c.repo,
          c.release.tagName, currentPlatform,
          message: e.toString());
      rethrow;
    }
  }

  /// 找出该仓库最近一次下载的产物文件（用于「重试安装」），无则返回 null
  Future<File?> lastDownloadedFile(RepoConfig repo,
      {String? downloadDir}) async {
    final dir = Directory(
        repoDownloadDir(repo.owner, repo.repo, baseDir: downloadDir));
    if (!await dir.exists()) return null;
    File? newest;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      // 跳过分片、续传临时文件与版本记录
      if (name.contains('.part') ||
          name.endsWith('.resume') ||
          name == versionFileName) {
        continue;
      }
      if (newest == null ||
          e.statSync().modified.isAfter(newest.statSync().modified)) {
        newest = e;
      }
    }
    return newest;
  }

  /// 仅重试「应用（安装）」步骤：复用已下载的文件，不重新下载
  Future<File> applyDownloaded(UpdateCheck c, File file) async {
    if (c.match == null) throw Exception('没有匹配的资产，无法安装');
    if (!await file.exists()) {
      throw InstallFailedException('已下载的文件不存在，需重新更新', file.path);
    }
    final updater = updaters.firstWhere(
      (u) => u.isApplicable(currentPlatform, c.match!.rule.strategy),
      orElse: () => throw Exception('无适用的更新器: ${c.match!.rule.strategy}'),
    );
    await notifications?.dispatch(NotificationEvent.updateStarted, c.repo,
        c.release.tagName, currentPlatform);
    try {
      await updater.apply(
        asset: c.match!.asset,
        localPath: file.path,
        repo: c.repo,
        rule: c.match!.rule,
      );
      await _writeVersionFile(c.repo, c.release.tagName, c.match!.asset, file);
      await notifications?.dispatch(NotificationEvent.updateSuccess, c.repo,
          c.release.tagName, currentPlatform);
      AppLog.info('重试安装成功 ${c.repo.fullName} → ${c.release.tagName}');
      return file;
    } catch (e) {
      AppLog.error('重试安装失败 ${c.repo.fullName}: $e');
      await notifications?.dispatch(NotificationEvent.updateFailed, c.repo,
          c.release.tagName, currentPlatform,
          message: e.toString());
      throw InstallFailedException('安装失败：$e', file.path);
    }
  }

  /// 在安装目录（未配置 installDir 时用下载目录）写入版本记录文件
  Future<void> _writeVersionFile(
      RepoConfig repo, String tag, Asset asset, File downloaded) async {
    final dir = (repo.installDir != null && repo.installDir!.isNotEmpty)
        ? repo.installDir!
        : downloaded.parent.path;
    try {
      final f = File(p.join(dir, versionFileName));
      await f.parent.create(recursive: true);
      await f.writeAsString('repo: ${repo.fullName}\n'
          'version: $tag\n'
          'asset: ${asset.name}\n'
          'updatedAt: ${DateTime.now().toIso8601String()}\n');
      AppLog.info('写入版本文件 ${f.path} → $tag');
    } catch (e) {
      AppLog.warn('写入版本文件失败: $e');
    }
  }
}

/// 依据检测结果生成人类可读的状态描述
String describeCheck(UpdateCheck c) {
  if (c.match == null) return '未找到匹配的资产';
  final installed = c.installedVersion;
  if (installed == null || installed.isEmpty) {
    return '未安装 · 最新 ${c.release.tagName}';
  }
  if (c.hasUpdate) return '已装 $installed → 可更新 ${c.release.tagName}';
  return '已是最新（已装 $installed）';
}
