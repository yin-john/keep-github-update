/// Updater 抽象：各端更新执行只依赖此接口，便于扩展与单测。
library;

import '../config/models.dart';
import '../github/release_model.dart';

abstract class Updater {
  /// 该更新器是否适用于指定平台 + 策略
  bool isApplicable(PlatformType platform, UpdateStrategy strategy);

  /// 执行更新（资产已下载到 localPath）
  Future<void> apply({
    required Asset asset,
    required String localPath,
    required RepoConfig repo,
    required AssetRule rule,
  });
}
