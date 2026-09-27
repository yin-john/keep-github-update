/// Windows 更新器：portable 解压覆盖 / installer（msi 或 setup.exe 静默安装）
library;

import '../core/config/models.dart';
import '../core/github/release_model.dart';
import '../core/platform/bridge.dart';
import '../core/updater/updater.dart';

class WindowsUpdater implements Updater {
  const WindowsUpdater(this.bridge);
  final PlatformBridge bridge;

  @override
  bool isApplicable(PlatformType p, UpdateStrategy s) =>
      p == PlatformType.windows &&
      (s == UpdateStrategy.portable || s == UpdateStrategy.installer);

  @override
  Future<void> apply({
    required Asset asset,
    required String localPath,
    required RepoConfig repo,
    required AssetRule rule,
  }) async {
    switch (rule.strategy) {
      case UpdateStrategy.portable:
        final target = repo.installDir;
        if (target == null || target.isEmpty) {
          throw Exception('portable 更新需要配置 installDir（安装目录）');
        }
        if (isArchiveFile(localPath)) {
          // 压缩包：解压覆盖（保留数据目录）
          await bridge.extractZip(localPath, target,
              preserve: rule.allPreservePaths);
        } else {
          // 单文件便携版（portable exe）：直接放入安装目录
          await bridge.placePortableFile(localPath, target);
        }
      case UpdateStrategy.installer:
        if (localPath.toLowerCase().endsWith('.msi')) {
          await bridge.installMsi(localPath, extraArgs: rule.installArgs);
        } else {
          final args =
              (rule.installArgs != null && rule.installArgs!.isNotEmpty)
                  ? rule.installArgs!
                  : '/S';
          await bridge.runSetup(localPath, args: args);
        }
      default:
        throw Exception('Windows 不支持的策略: ${rule.strategy}');
    }
  }
}
