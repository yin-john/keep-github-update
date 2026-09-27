/// 仓库检测状态（列表页与后台自动检测共用同一份状态，切换 Tab / 后台检测都能同步）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/models.dart';
import '../../core/config/repo_display.dart';
import '../../core/scheduler/check_schedule.dart';
import '../../core/scheduler/update_scheduler.dart';
import '../../core/updater/update_service.dart';
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
    final merged = r.copyWith(
      lastCheckedAt: formatTimestamp(now),
      lastInstalledTag:
          (installed != null && installed.isNotEmpty) ? installed : null,
    );
    if (merged.lastCheckedAt == r.lastCheckedAt &&
        merged.lastInstalledTag == r.lastInstalledTag) {
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
      ref.read(configProvider.notifier).updateRepo(
          r.copyWith(packageName: id.packageName, moduleId: id.moduleId));
    } catch (_) {
      // 反查失败不影响检测
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
      await _learnIdentity(r, c.installedVersion ?? r.lastInstalledTag);
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

/// 读取 APK 的软件名称与图标，写入仓库配置（Android，需开启「自动获取」）
Future<void> fetchApkInfoForRepo(
    WidgetRef ref, RepoConfig r, String apkPath) async {
  if (!r.fetchApkInfo || !r.isApkRepo) return;
  if (!Platform.isAndroid) return;
  try {
    final info =
        await ref.read(androidEnvProvider).apkAppInfo(apkPath);
    if (info.isEmpty) {
      AppLog.warn('未能从 ${r.fullName} 的 APK 读取名称/图标');
      return;
    }
    final cur = ref.read(configProvider).repos.firstWhere(
          (e) => e.fullName == r.fullName,
          orElse: () => r,
        );
    ref.read(configProvider.notifier).updateRepo(cur.copyWith(
          apkLabel: (info.label?.isNotEmpty ?? false) ? info.label : null,
          apkIconPath: (info.iconPath?.isNotEmpty ?? false)
              ? info.iconPath
              : null,
        ));
    AppLog.info('已获取 ${r.fullName} 的 APK 信息：${info.label ?? '(无名称)'}'
        '${info.iconPath == null ? '' : ' · 图标 ${info.iconPath}'}');
  } catch (e) {
    AppLog.warn('读取 APK 名称/图标失败：$e');
  }
}
