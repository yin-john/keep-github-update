/// Linux 更新器：portable 解压覆盖 / docker 拉取并重建容器
library;

import '../core/config/models.dart';
import '../core/github/release_model.dart';
import '../core/platform/bridge.dart';
import '../core/updater/updater.dart';

class LinuxUpdater implements Updater {
  const LinuxUpdater(this.bridge);
  final PlatformBridge bridge;

  @override
  bool isApplicable(PlatformType p, UpdateStrategy s) =>
      p == PlatformType.linux &&
      (s == UpdateStrategy.portable || s == UpdateStrategy.docker);

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
          // 单文件便携版（AppImage 等）：直接放入安装目录
          await bridge.placePortableFile(localPath, target);
        }
      case UpdateStrategy.docker:
        final image = repo.containerName != null && repo.containerName!.isNotEmpty
            ? repo.containerName!
            : repo.fullName.toLowerCase();
        await bridge.dockerUpdate(image,
            containerName: repo.containerName, runArgs: repo.dockerRunArgs);
      default:
        throw Exception('Linux 不支持的策略: ${rule.strategy}');
    }
  }
}
