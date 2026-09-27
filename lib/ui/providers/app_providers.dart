/// GUI 状态管理（Riverpod）
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_paths.dart';
import '../../core/config/config_repository.dart';
import '../../core/config/models.dart';
import '../../core/log/app_log.dart';
import '../../core/github/api_client.dart';
import '../../core/github/direct_link_fetcher.dart';
import '../../core/github/release_fetcher.dart';
import '../../core/mirror/mirror_resolver.dart';
import '../../core/matcher/asset_matcher.dart';
import '../../core/download/download_manager.dart';
import '../../core/updater/update_service.dart';
import '../../platforms/updater_registry.dart';
import '../../core/notification/notification_dispatcher.dart';
import '../../core/notification/system_notifier.dart';
import '../../core/notification/webhook_notifier.dart';
import '../../core/platform/android_env.dart';
import '../../core/platform/bridge.dart';
import '../../platforms/flutter_android_env.dart';

/// 平台桥接（打开目录等 OS 操作）
final platformBridgeProvider =
    Provider<PlatformBridge>((_) => const DefaultPlatformBridge());

/// Android 设备能力（权限、root/Shizuku、签名与包信息）；其它平台为安全空实现
final androidEnvProvider =
    Provider<AndroidEnv>((_) => const FlutterAndroidEnv());

final configRepoProvider =
    Provider<ConfigRepository>((ref) => ConfigRepository(defaultConfigPath()));

final configProvider =
    StateNotifierProvider<ConfigNotifier, AppConfig>((ref) {
  return ConfigNotifier(ref.watch(configRepoProvider));
});

/// 由 main 覆写为已初始化的 FlutterSystemNotifier
final systemNotifierProvider =
    Provider<SystemNotifier>((ref) => throw UnimplementedError('由 main 覆写'));

/// 当前设备架构（由 main 在启动时解析并覆写；非 Android 端为 any）
final deviceArchProvider =
    Provider<TargetArch>((ref) => TargetArch.any);

final updateServiceProvider = Provider<UpdateService>((ref) {
  final cfg = ref.watch(configProvider);
  final system = ref.watch(systemNotifierProvider);
  final notifications = NotificationDispatcher(
    system: system,
    webhook: WebhookNotifier(),
    config: cfg,
  );
  return createUpdateServiceForCurrentPlatform(
    fetcher: ReleaseFetcher(
      api: GitHubApiClient(token: cfg.githubToken),
      direct: DirectLinkFetcher(),
    ),
    mirror: MirrorResolver(cfg.mirrors),
    matcher: AssetMatcher(),
    downloader: DownloadManager(threads: cfg.downloadThreads),
    notifications: notifications,
    androidEnv: ref.watch(androidEnvProvider),
    forceIgnoreSignature: cfg.forceInstallIgnoreSignature,
    deviceArch: ref.watch(deviceArchProvider),
    defaultApkInstallMethod: cfg.defaultApkInstallMethod,
  );
});

/// 单个下载任务（「下载」选项卡展示进行中的下载）
class DownloadTask {

  const DownloadTask({
    required this.repo,
    required this.token,
    this.status = '准备中',
    this.progress,
    this.speed = 0,
    this.active = true,
  });
  final String repo; // owner/repo
  final String status;
  final double? progress; // 0..1
  final double speed; // 字节/秒
  final bool active;
  final CancelToken token;

  DownloadTask copyWith({
    String? status,
    double? progress,
    double? speed,
    bool? active,
  }) =>
      DownloadTask(
        repo: repo,
        token: token,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        speed: speed ?? this.speed,
        active: active ?? this.active,
      );
}

class DownloadsNotifier extends StateNotifier<List<DownloadTask>> {
  DownloadsNotifier() : super(const []);

  /// 开始一个下载任务，返回可中断的 CancelToken
  CancelToken start(String repo) {
    final token = CancelToken();
    state = [
      ...state.where((t) => t.repo != repo),
      DownloadTask(repo: repo, token: token),
    ];
    return token;
  }

  void progress(String repo,
      {double? progress, double? speed, String? status}) {
    state = [
      for (final t in state)
        t.repo == repo
            ? t.copyWith(
                progress: progress,
                speed: speed,
                status: status,
                active: true)
            : t,
    ];
  }

  void finish(String repo, String status) {
    state = [
      for (final t in state)
        t.repo == repo
            ? t.copyWith(status: status, active: false, speed: 0)
            : t,
    ];
  }

  void cancel(String repo) {
    for (final t in state) {
      if (t.repo == repo) t.token.cancel();
    }
  }

  void clearFinished() => state = state.where((t) => t.active).toList();
}

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, List<DownloadTask>>(
        (_) => DownloadsNotifier());

class ConfigNotifier extends StateNotifier<AppConfig> {

  ConfigNotifier(this.repo)
      : super(const AppConfig(
            webhook: WebhookConfig(
                enabled: false, url: '', events: NotificationEvent.values))) {
    _ready = _load();
  }
  final ConfigRepository repo;
  late final Future<void> _ready;

  /// 首次加载完成（供测试与导入后使用，避免与加载竞争）
  Future<void> get ready => _ready;

  Future<void> _load() async => state = await repo.load();

  /// 从磁盘重新加载（用于导入配置后刷新界面）
  Future<void> reload() async => state = await repo.load();

  void addRepo(RepoConfig r) {
    state = state.copyWith(repos: [...state.repos, r]);
    repo.save(state);
    AppLog.info('添加仓库 ${r.fullName}（规则 ${r.assetRules.length} 条）');
  }

  void updateRepo(RepoConfig r) {
    state = state.copyWith(
        repos: state.repos.map((e) => e.fullName == r.fullName ? r : e).toList());
    repo.save(state);
    AppLog.info('更新仓库配置 ${r.fullName}');
  }

  /// 取某仓库在当前配置中的最新版本（未找到时原样返回）。
  ///
  /// 调用方持有的 [r] 往往是较早的快照；若直接 `r.copyWith(...)` 后
  /// [updateRepo] 会整体替换，抹掉期间其它流程写入的字段
  /// （如图标/软件名/已下载版本/包名）。局部更新前应先取最新对象。
  RepoConfig freshRepo(RepoConfig r) {
    final i = state.repos.indexWhere((e) => e.fullName == r.fullName);
    return i < 0 ? r : state.repos[i];
  }

  Future<void> removeRepo(String fullName) async {
    final removed =
        state.repos.where((e) => e.fullName == fullName).toList();
    state = state.copyWith(
        repos: state.repos.where((e) => e.fullName != fullName).toList());
    await repo.save(state);
    AppLog.info('移除仓库 $fullName');
    // 清理该仓库残留的下载文件
    for (final r in removed) {
      try {
        await clearRepoDownloads(r.owner, r.repo, baseDir: state.downloadDir);
        AppLog.info('已清理下载目录 ${r.owner}@${r.repo}');
      } catch (e) {
        AppLog.warn('清理下载目录失败: $e');
      }
    }
  }

  /// 清空全部仓库；[deleteDownloads] 为真时同时删除各自的下载目录
  Future<void> clearRepos({bool deleteDownloads = false}) async {
    final removed = state.repos;
    if (removed.isEmpty) return;
    state = state.copyWith(repos: const []);
    await repo.save(state);
    if (deleteDownloads) {
      for (final r in removed) {
        try {
          await clearRepoDownloads(r.owner, r.repo, baseDir: state.downloadDir);
        } catch (e) {
          AppLog.warn('清理下载目录失败: $e');
        }
      }
    }
    AppLog.info('已清空全部仓库（${removed.length} 个）');
  }

  void setConfig(AppConfig cfg) {
    state = cfg;
    repo.save(state);
  }
}
