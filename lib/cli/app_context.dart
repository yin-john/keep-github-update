/// CLI/TUI 共享：配置路径解析与服务装配
library;

import '../core/config/config_repository.dart';
import '../core/config/models.dart';
import '../core/github/api_client.dart';
import '../core/github/direct_link_fetcher.dart';
import '../core/github/release_fetcher.dart';
import '../core/mirror/mirror_resolver.dart';
import '../core/matcher/asset_matcher.dart';
import '../core/download/download_manager.dart';
import '../core/updater/update_service.dart';
import '../platforms/updater_registry.dart';
import '../core/notification/notification_dispatcher.dart';
import '../core/notification/system_notifier.dart';
import '../core/notification/webhook_notifier.dart';
import '../core/platform/bridge.dart';

// 路径相关统一由 core 提供（应用数据放在同名目录），此处再导出以便既有 import 继续可用
export '../core/config/app_paths.dart'
    show appDirName, appDataDir, defaultConfigPath, defaultDownloadDir;

class AppContext {

  AppContext({
    required this.configRepo,
    required this.config,
    required this.service,
  });
  final ConfigRepository configRepo;
  final AppConfig config;
  final UpdateService service;
}

Future<AppContext> loadContext(String configPath) async {
  final configRepo = ConfigRepository(configPath);
  final config = await configRepo.load();
  const bridge = DefaultPlatformBridge();
  final notifications = NotificationDispatcher(
    system: const ConsoleSystemNotifier(bridge),
    webhook: WebhookNotifier(),
    config: config,
  );
  final service = createUpdateServiceForCurrentPlatform(
    fetcher: ReleaseFetcher(
      api: GitHubApiClient(token: config.githubToken),
      direct: DirectLinkFetcher(),
    ),
    mirror: MirrorResolver(config.mirrors),
    matcher: AssetMatcher(),
    downloader: DownloadManager(threads: config.downloadThreads),
    notifications: notifications,
    deviceArch: await bridge.deviceArch(),
    defaultApkInstallMethod: config.defaultApkInstallMethod,
  );
  return AppContext(configRepo: configRepo, config: config, service: service);
}
