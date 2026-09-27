/// 平台装配层：将具体平台更新器（Windows/Android/Linux）与核心编排服务组合。
/// 放在 platforms 层以避免 core 反向依赖 platforms。
library;

import '../core/config/models.dart';
import '../core/github/release_fetcher.dart';
import '../core/mirror/mirror_resolver.dart';
import '../core/matcher/asset_matcher.dart';
import '../core/download/download_manager.dart';
import '../core/updater/update_service.dart';
import '../core/notification/notification_dispatcher.dart';
import '../core/platform/android_env.dart';
import '../core/platform/bridge.dart';
import '../core/platform/platform_utils.dart';
import 'windows_updater.dart';
import 'android_updater.dart';
import 'linux_updater.dart';

/// 按当前运行平台装配更新编排服务：自动注入对应的平台更新器与桥接实现。
UpdateService createUpdateServiceForCurrentPlatform({
  required ReleaseFetcher fetcher,
  required MirrorResolver mirror,
  required AssetMatcher matcher,
  required DownloadManager downloader,
  required NotificationDispatcher? notifications,
  PlatformBridge? bridge,
  AndroidEnv? androidEnv,
  bool forceIgnoreSignature = false,
  TargetArch? deviceArch,
  InstallMethod defaultApkInstallMethod = InstallMethod.root,
}) {
  final b = bridge ?? const DefaultPlatformBridge();
  return UpdateService(
    fetcher: fetcher,
    mirror: mirror,
    matcher: matcher,
    downloader: downloader,
    updaters: [
      WindowsUpdater(b),
      AndroidUpdater(b, defaultApkInstallMethod, androidEnv, forceIgnoreSignature),
      LinuxUpdater(b),
    ],
    currentPlatform: currentPlatformType(),
    notifications: notifications,
    deviceArch: deviceArch,
    device: b,
    androidEnv: androidEnv,
  );
}
