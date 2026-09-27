/// 仓库检测状态（列表页与后台自动检测共用同一份状态，切换 Tab / 后台检测都能同步）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_paths.dart';
import '../../core/config/models.dart';
import '../../core/config/repo_display.dart';
import '../../core/platform/apk_info.dart';
import '../../core/platform/apk_local_info.dart';
import '../../core/scheduler/check_schedule.dart';
import '../../core/scheduler/update_scheduler.dart';
import '../../core/updater/update_service.dart';
import '../../core/version/installed_version.dart';
import '../../core/log/app_log.dart';
import 'app_providers.dart';

/// 单个仓库的检测状态
class RepoCheckState {
  const RepoCheckState({
    this.latest,
    this.hasUpdate,
    this.status,
    this.checking = false,
    this.check,
    this.canRetryInstall = false,
    this.lastCheckedAt,
  });

  final String? latest; // 仓库最新版本 tag
  final bool? hasUpdate; // 是否可更新（用于着色）
  final String? status; // 状态文案
  final bool checking; // 正在检测
  final UpdateCheck? check; // 最近一次检测结果（「重试安装」复用）
  final bool canRetryInstall; // 已下载但安装失败，可重试
  final DateTime? lastCheckedAt;

  RepoCheckState copyWith({
    String? latest,
    bool? hasUpdate,
    String? status,
    bool? checking,
    UpdateCheck? check,
    bool? canRetryInstall,
    DateTime? lastCheckedAt,
  }) =>
      RepoCheckState(
        latest: latest ?? this.latest,
        hasUpdate: hasUpdate ?? this.hasUpdate,
        status: status ?? this.status,
        checking: checking ?? this.checking,
        check: check ?? this.check,
        canRetryInstall: canRetryInstall ?? this.canRetryInstall,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      );
}

class CheckNotifier extends StateNotifier<Map<String, RepoCheckState>> {
  CheckNotifier(this.ref) : super(const {});
  final Ref ref;

  RepoCheckState of(String key) => state[key] ?? const RepoCheckState();

  bool get anyChecking => state.values.any((s) => s.checking);

  void _patch(String key, RepoCheckState Function(RepoCheckState) fn) {
    state = {...state, key: fn(of(key))};
  }

  /// 写入状态文案（更新流程也会调用）
  void setStatus(String key, String status,
      {bool? hasUpdate, bool? canRetryInstall}) {
    _patch(
        key,
        (s) => s.copyWith(
            status: status,
            hasUpdate: hasUpdate,
            canRetryInstall: canRetryInstall));
  }

  /// 把设备上读到的真实已装版本同步进配置，并记录本次检测时间
  void _persistAfterCheck(RepoConfig r, UpdateCheck c, DateTime now) {
    final installed = c.installedVersion;
    // 以最新配置为基，避免覆盖期间其它流程写入的字段（如图标/已下载版本）
    final cur = ref.read(configProvider.notifier).freshRepo(r);
    final merged = cur.copyWith(
      lastCheckedAt: formatTimestamp(now),
      lastInstalledTag:
          (installed != null && installed.isNotEmpty) ? installed : null,
    );
    if (merged.lastCheckedAt == cur.lastCheckedAt &&
        merged.lastInstalledTag == cur.lastInstalledTag) {
      return;
    }
    ref.read(configProvider.notifier).updateRepo(merged);
  }

  /// 记录一次检测结果（更新流程复用，避免重复请求网络）
  void setResult(String key, UpdateCheck c, {String? status}) {
    _patch(
        key,
        (s) => s.copyWith(
              latest: c.release.tagName,
              hasUpdate: c.match == null ? null : c.hasUpdate,
              check: c,
              status: status ?? describeCheck(c),
            ));
  }

  /// 依据已装版本反查补全包名 / 模块 ID（更新成功后由界面调用）
  Future<void> learnIdentityFor(RepoConfig r, String tag) =>
      _learnIdentity(r, tag);

  /// 从仓库下载目录里已下载的 APK 提取名称/图标（结果落盘到该目录）
  Future<ApkAppInfo?> _extractLocalApkInfo(RepoConfig r) async {
    try {
      final cfg = ref.read(configProvider);
      final dir = repoDownloadDir(r.owner, r.repo, baseDir: cfg.downloadDir);
      return await extractApkInfoIntoDir(ref.read(androidEnvProvider), dir);
    } catch (e) {
      AppLog.warn('从本地 APK 提取名称/图标失败：$e');
      return null;
    }
  }

  /// 从设备上已安装的应用提取名称/包名/版本/图标（落盘到下载目录）
  Future<ApkAppInfo?> _extractInstalledAppInfo(RepoConfig r) async {
    try {
      final cfg = ref.read(configProvider);
      final dir = repoDownloadDir(r.owner, r.repo, baseDir: cfg.downloadDir);
      return await extractInstalledAppInfoIntoDir(
          ref.read(androidEnvProvider), dir, r.packageName!);
    } catch (e) {
      AppLog.warn('从已安装应用提取名称/图标失败：$e');
      return null;
    }
  }

  /// Android：补全名称/图标等显示信息。
  ///
  /// 提取优先级：
  /// 1. 本地已下载过 APK → 直接从 APK 提取（最准确）；
  /// 2. **从未下载过**且已安装版本与仓库最新版本一致 → 从已安装的应用提取
  ///    （避免「已装旧版但仓库已有新版」时提取到旧版信息）。
  ///
  /// 已有名称与图标时不跳过：Xposed 分类标记可能尚未识别（旧版缓存），
  /// 依靠产物缓存与 [_applyApkInfo] 的无变化短路把开销降到最低。
  Future<void> _fillApkInfo(RepoConfig r, UpdateCheck c) async {
    if (!r.fetchApkInfo || !r.isApkRepo) return;
    if (!Platform.isAndroid) return;
    final fresh = ref.read(configProvider.notifier).freshRepo(r);
    final dir = repoDownloadDir(r.owner, r.repo,
        baseDir: ref.read(configProvider).downloadDir);
    ApkAppInfo? info;
    var fromDownload = false;
    if (newestApkInDir(dir) != null) {
      info = await _extractLocalApkInfo(r);
      fromDownload = true;
      if (info == null || info.isEmpty) {
        AppLog.warn('补全 ${r.fullName}：从本地 APK 提取名称/图标失败');
      }
    } else if (fresh.downloadedVersion == null && c.match != null) {
      if (fresh.packageName?.isEmpty ?? true) {
        AppLog.info('补全 ${r.fullName}：未下载过 APK 且未识别包名，'
            '无法从已安装应用提取（可在仓库编辑页手动填写包名）');
      } else {
        final installed = await ref
            .read(updateServiceProvider)
            .resolveInstalledVersion(fresh);
        AppLog.info('补全 ${r.fullName}：已装版本 ${installed ?? '未知'}，'
            '仓库最新 ${c.release.tagName}');
        if (installed != null &&
            installed.isNotEmpty &&
            versionMatches(installed, c.release.tagName)) {
          info = await _extractInstalledAppInfo(fresh);
          if (info == null || info.isEmpty) {
            AppLog.warn('补全 ${r.fullName}：从已安装应用提取失败');
          }
        }
      }
    }
    if (info != null && info.isNotEmpty) {
      _applyApkInfo(ref.read(configProvider), ref.read(configProvider.notifier),
          r, info,
          setDownloadedVersion: fromDownload);
    }
  }

  /// 依据设备上读到的版本反查并补全包名 / 模块 ID
  Future<void> _learnIdentity(RepoConfig r, String? tag) async {
    if ((r.packageName?.isNotEmpty ?? false) ||
        (r.moduleId?.isNotEmpty ?? false)) {
      return;
    }
    if (tag == null || tag.isEmpty) return;
    try {
      final id = await ref.read(updateServiceProvider).detectIdentity(r, tag);
      if (id == null) return;
      if (id.packageName == null && id.moduleId == null) return;
      // 以最新配置为基，避免覆盖期间其它流程写入的字段（如图标/已下载版本）
      ref.read(configProvider.notifier).updateRepo(
          ref.read(configProvider.notifier).freshRepo(r).copyWith(
              packageName: id.packageName, moduleId: id.moduleId));
      AppLog.info('反查 ${r.fullName} 成功：'
          'packageName=${id.packageName ?? '-'} moduleId=${id.moduleId ?? '-'}');
    } catch (e) {
      AppLog.warn('反查 ${r.fullName} 包名/模块 ID 失败：$e');
    }
  }

  /// 检测单个仓库；[notify] 为真且发现有更新时弹系统通知
  Future<UpdateCheck?> checkOne(RepoConfig r, {bool notify = true}) async {
    final key = r.fullName;
    _patch(key, (s) => s.copyWith(checking: true));
    final now = DateTime.now();
    try {
      final c = await ref.read(updateServiceProvider).check(r);
      state = {
        ...state,
        key: of(key).copyWith(
          latest: c.release.tagName,
          hasUpdate: c.match == null ? null : c.hasUpdate,
          status: describeCheck(c),
          checking: false,
          check: c,
          lastCheckedAt: now,
        ),
      };
      _persistAfterCheck(r, c, now);
      // 反查包名/模块 ID：优先用设备上真实读到的已装版本；
      // 从未追踪过的仓库（无已装版本记录）用仓库最新 tag 兜底——
      // 若设备上恰好有唯一一个包的版本与最新 tag 一致，即认定为该应用
      // （「从外部安装且已是最新版」的场景），否则永远学不到包名，
      // 图标/分类/启动按钮都无法生效。
      await _learnIdentity(
          r, c.installedVersion ?? r.lastInstalledTag ?? c.release.tagName);
      await _fillApkInfo(r, c);
      if (notify && c.hasUpdate && r.notificationsEnabled) {
        await ref.read(systemNotifierProvider).show(
            '${_displayName(r)} 有可用更新',
            '检测到适用于当前平台的新版本：${c.release.tagName}',
            NotificationLevel.info);
      }
      return c;
    } catch (e) {
      _patch(
          key,
          (s) => s.copyWith(checking: false, status: '检测失败: $e'));
      return null;
    }
  }

  /// 批量检测（「检测全部」「检测所选」与后台调度共用）
  Future<void> checkMany(Iterable<RepoConfig> repos, {bool notify = false}) async {
    for (final r in repos) {
      await checkOne(r, notify: notify);
    }
  }

  static String _displayName(RepoConfig r) =>
      resolveRepoTitle(
              fullName: r.fullName,
              displayName: r.displayName,
              apkLabel: r.apkLabel)
          .primary;
}

final checkProvider =
    StateNotifierProvider<CheckNotifier, Map<String, RepoCheckState>>(
        (ref) => CheckNotifier(ref));

/// 自动检测调度器：按「全局间隔 + 仓库级覆盖」周期性触发静默检测。
/// 由 AppShell 在启动/配置变更时 start / stop。
final schedulerProvider = Provider<UpdateScheduler>((ref) {
  late final UpdateScheduler scheduler;
  scheduler = UpdateScheduler(
    repos: () => ref.read(configProvider).repos,
    globalInterval: () => ref.read(configProvider).checkIntervalMinutes,
    onDue: (r) async {
      AppLog.info('自动检测（间隔到期）：${r.fullName}');
      await ref.read(checkProvider.notifier).checkOne(r);
    },
    onTick: () async {
      final cfg = ref.read(configProvider);
      if (!cfg.backgroundKeepAlive) return;
      final env = ref.read(androidEnvProvider);
      if (!env.isAndroid) return;
      await env.updateBackgroundNotification(
        'GRKU 后台运行中',
        '下次检测：${describeTimeUntil(scheduler.nextCheckAt(), DateTime.now())}',
      );
    },
    tick: const Duration(minutes: 1),
  );
  ref.onDispose(scheduler.stop);
  return scheduler;
});

/// 获取仓库的 APK 名称与图标（Android，需开启「自动获取」）。
///
/// **优先使用本地已下载的 APK**：
/// - [apkPath] 指定（刚下载完成）→ 直接从该 APK 提取；
/// - 否则在仓库的下载目录里找最新的 `*.apk` 提取。
/// 产物落在下载目录：图标 `app_icon.png`、名称 `app_name.txt`，
/// 并写入仓库配置供列表显示（图标/名称取自这些本地文件）。
Future<ApkAppInfo?> fetchApkInfoForRepo(
    WidgetRef ref, RepoConfig r,
    {String? apkPath}) async {
  if (!r.fetchApkInfo || !r.isApkRepo) return null;
  if (!Platform.isAndroid) return null;
  try {
    final cfg = ref.read(configProvider);
    final dir = repoDownloadDir(r.owner, r.repo, baseDir: cfg.downloadDir);
    final info = await extractApkInfoIntoDir(
        ref.read(androidEnvProvider), dir,
        apkPath: apkPath);
    if (info == null || info.isEmpty) {
      AppLog.warn('未能从 ${r.fullName} 的 APK 读取名称/图标'
          '${apkPath == null ? '（下载目录中没有可用的 APK）' : ''}');
      return null;
    }
    _applyApkInfo(ref.read(configProvider), ref.read(configProvider.notifier),
        r, info);
    AppLog.info('已获取 ${r.fullName} 的 APK 信息：${info.label ?? '(无名称)'}'
        '${info.iconPath == null ? '' : ' · 图标 ${info.iconPath}'}');
    return info;
  } catch (e) {
    AppLog.warn('读取 APK 名称/图标失败：$e');
    return null;
  }
}

/// 把提取到的名称/包名/版本/图标写入仓库配置
/// [config] 为调用时的配置快照（StateNotifier.state 不能在外部访问）；
/// [setDownloadedVersion] 为假时不动已下载版本（信息来自已安装应用）。
/// 无任何字段变化时不写盘（每次检测都会尝试补全信息）。
void _applyApkInfo(
    AppConfig config, ConfigNotifier notifier, RepoConfig r, ApkAppInfo info,
    {bool setDownloadedVersion = true}) {
  final cur = config.repos.firstWhere(
    (e) => e.fullName == r.fullName,
    orElse: () => r,
  );
  final merged = cur.copyWith(
    apkLabel: (info.label?.isNotEmpty ?? false) ? info.label : null,
    apkIconPath: (info.iconPath?.isNotEmpty ?? false) ? info.iconPath : null,
    downloadedVersion: (setDownloadedVersion &&
            (info.version?.isNotEmpty ?? false))
        ? info.version
        : null,
    // Xposed 模块标记（分类分栏用）；非 Xposed 应用会写 false
    xposedModule: info.xposed,
    // 自动补全包名（用于读取设备上的已装版本）；用户已配置时不覆盖
    packageName: ((r.packageName?.isEmpty ?? true) &&
            (info.packageName?.isNotEmpty ?? false))
        ? info.packageName
        : null,
  );
  final changed = merged.apkLabel != cur.apkLabel ||
      merged.apkIconPath != cur.apkIconPath ||
      merged.xposedModule != cur.xposedModule ||
      merged.packageName != cur.packageName ||
      (setDownloadedVersion &&
          merged.downloadedVersion != cur.downloadedVersion);
  if (!changed) return;
  notifier.updateRepo(merged);
}
