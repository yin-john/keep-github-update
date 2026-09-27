/// 应用版本号（CLI/TUI/GUI 共用）。
///
/// 取值优先级：
/// 1. 编译期注入：`dart compile exe -DGRKU_VERSION=1.2.3 ...`（CI 可用）
/// 2. 默认值 [appVersionDefault]，需与 `pubspec.yaml` 的 `version` 一致；
///    有单元测试（test/app_version_test.dart）保证两者不漂移。
library;

/// 源码中的默认版本（应与 pubspec.yaml 的 version 相同，不含 +构建号）
const String appVersionDefault = '0.2.8';

/// 当前版本号
const String appVersion = String.fromEnvironment(
  'GRKU_VERSION',
  defaultValue: appVersionDefault,
);
