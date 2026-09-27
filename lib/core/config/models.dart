/// 全局配置数据模型：仓库、镜像、资产匹配规则、Webhook、通知。
library;

import 'dart:convert';

/// 目标平台
enum PlatformType { android, windows, linux }

extension PlatformTypeX on PlatformType {
  /// 该平台可用的更新策略（用于 UI 过滤，避免出现其它平台专属选项）
  List<UpdateStrategy> get strategies {
    switch (this) {
      case PlatformType.windows:
        return const [UpdateStrategy.portable, UpdateStrategy.installer];
      case PlatformType.linux:
        return const [UpdateStrategy.portable, UpdateStrategy.docker];
      case PlatformType.android:
        return const [UpdateStrategy.module, UpdateStrategy.apk];
    }
  }

  /// 该策略是否适用于本平台
  bool supportsStrategy(UpdateStrategy strategy) =>
      strategies.contains(strategy);

  /// 是否需要 APK/模块 安装授权方式（仅 Android）
  bool get usesApkInstallMethod => this == PlatformType.android;
}

/// 更新策略（决定平台专属的执行方式）
enum UpdateStrategy {
  portable, // Windows/Linux：解压覆盖目录
  installer, // Windows：msi/setup.exe 静默安装
  docker, // Linux：docker 拉取 + 重建容器
  module, // Android：Magisk/KernelSU 模块刷入
  apk, // Android：root 安装/更新应用 APK
}

extension UpdateStrategyX on UpdateStrategy {
  String get label {
    switch (this) {
      case UpdateStrategy.portable:
        return 'Portable';
      case UpdateStrategy.installer:
        return 'Installer';
      case UpdateStrategy.docker:
        return 'Docker';
      case UpdateStrategy.module:
        return 'Magisk/KernelSU 模块';
      case UpdateStrategy.apk:
        return 'APK (root)';
    }
  }

  /// portable/installer：安装到本地目录（Windows/Linux）
  bool get usesInstallDir =>
      this == UpdateStrategy.portable || this == UpdateStrategy.installer;

  /// docker：需要容器名与 docker run 参数（Linux）
  bool get isDocker => this == UpdateStrategy.docker;

  /// module/apk：需要 APK/模块 安装授权方式（Android）
  bool get usesApkInstallMethod =>
      this == UpdateStrategy.module || this == UpdateStrategy.apk;
}

/// 镜像改写模式
enum MirrorMode { prefix, regex }

/// 通知触发事件
enum NotificationEvent {
  updateAvailable,
  updateStarted,
  updateSuccess,
  updateFailed,
}

extension NotificationEventX on NotificationEvent {
  String get name {
    switch (this) {
      case NotificationEvent.updateAvailable:
        return 'updateAvailable';
      case NotificationEvent.updateStarted:
        return 'updateStarted';
      case NotificationEvent.updateSuccess:
        return 'updateSuccess';
      case NotificationEvent.updateFailed:
        return 'updateFailed';
    }
  }

  static NotificationEvent fromName(String s) => NotificationEvent.values.firstWhere(
        (e) => e.name == s,
        orElse: () => NotificationEvent.updateAvailable,
      );
}

/// 通知级别
enum NotificationLevel { info, success, warning, error }

/// 校验和算法类型
enum ChecksumType { sha256, md5 }

extension ChecksumTypeX on ChecksumType {
  String get ext {
    switch (this) {
      case ChecksumType.sha256:
        return 'sha256';
      case ChecksumType.md5:
        return 'md5';
    }
  }
}

/// 目标架构（主要用于 Android 资产区分）
enum TargetArch { any, arm32, arm64 }

extension TargetArchX on TargetArch {
  String get label {
    switch (this) {
      case TargetArch.any:
        return '不限';
      case TargetArch.arm32:
        return 'ARM32 (armeabi-v7a)';
      case TargetArch.arm64:
        return 'ARM64 (arm64-v8a)';
    }
  }

  /// 在产物文件名中用于识别该架构的常见关键字
  List<String> get tokens {
    switch (this) {
      case TargetArch.any:
        return const [];
      case TargetArch.arm32:
        return const ['arm32', 'armv7', 'armeabi', 'arm-v7a', 'armeabi-v7a'];
      case TargetArch.arm64:
        return const ['arm64', 'aarch64', 'arm64-v8a', 'arm-v8a'];
    }
  }
}

/// APK 静默安装授权方式
/// APK 安装授权方式：
/// - root / shizuku：静默安装（需要授权）
/// - normal：调用系统安装器（普通安装，无需 root，用户手动确认）
enum InstallMethod { root, shizuku, normal }

extension InstallMethodX on InstallMethod {
  String get label {
    switch (this) {
      case InstallMethod.root:
        return 'Root';
      case InstallMethod.shizuku:
        return 'Shizuku';
      case InstallMethod.normal:
        return '普通安装（系统安装器）';
    }
  }

  /// 是否需要 root/Shizuku 等特权
  bool get needsPrivilege => this != InstallMethod.normal;
}

/// 单条资产匹配规则：在某平台下用文件名正则匹配产物
class AssetRule { // installer：追加到安装命令的额外参数

  const AssetRule({
    required this.platform,
    required this.strategy,
    required this.nameRegex,
    this.checksumRegex,
    this.verifyChecksum = false,
    this.checksumType = ChecksumType.sha256,
    this.arch = TargetArch.any,
    this.preservePaths = const [],
    this.preserveFiles = const [],
    this.installArgs,
  });

  factory AssetRule.fromJson(Map<String, dynamic> j) => AssetRule(
        platform: PlatformType.values.firstWhere((e) => e.name == j['platform']),
        strategy: UpdateStrategy.values.firstWhere((e) => e.name == j['strategy']),
        nameRegex: j['nameRegex'] as String,
        checksumRegex: j['checksumRegex'] as String?,
        verifyChecksum: j['verifyChecksum'] as bool? ?? false,
        checksumType: ChecksumType.values.firstWhere(
          (e) => e.name == (j['checksumType'] ?? 'sha256'),
          orElse: () => ChecksumType.sha256,
        ),
        arch: TargetArch.values.firstWhere(
          (e) => e.name == (j['arch'] ?? 'any'),
          orElse: () => TargetArch.any,
        ),
        preservePaths: ((j['preservePaths'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        preserveFiles: ((j['preserveFiles'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        installArgs: j['installArgs'] as String?,
      );
  final PlatformType platform;
  final UpdateStrategy strategy;
  final String nameRegex;
  final String? checksumRegex; // 可选：自定义定位校验文件的文件名正则（留空则按默认规则推断）
  final bool verifyChecksum; // 是否下载后对照 release 下的校验文件验证完整性
  final ChecksumType checksumType; // 校验算法：sha256 / md5
  final TargetArch arch; // 目标架构（any 表示不限定；Android 用于区分 arm32/arm64 产物）
  final List<String> preservePaths; // portable：安装目录中「排除覆盖/保留」的目录路径正则（数据目录等）
  final List<String> preserveFiles; // portable：安装目录中「排除覆盖/保留」的文件路径正则（数据文件等）
  final String? installArgs;

  /// 解压覆盖时需要保留的全部路径正则（目录 + 文件）
  List<String> get allPreservePaths => [...preservePaths, ...preserveFiles];

  Map<String, dynamic> toJson() => {
        'platform': platform.name,
        'strategy': strategy.name,
        'nameRegex': nameRegex,
        if (checksumRegex != null) 'checksumRegex': checksumRegex,
        if (verifyChecksum) 'verifyChecksum': verifyChecksum,
        if (checksumType != ChecksumType.sha256) 'checksumType': checksumType.name,
        if (arch != TargetArch.any) 'arch': arch.name,
        if (preservePaths.isNotEmpty) 'preservePaths': preservePaths,
        if (preserveFiles.isNotEmpty) 'preserveFiles': preserveFiles,
        if (installArgs != null) 'installArgs': installArgs,
      };

  @override
  bool operator ==(Object other) =>
      other is AssetRule &&
      other.platform == platform &&
      other.strategy == strategy &&
      other.nameRegex == nameRegex &&
      other.checksumRegex == checksumRegex &&
      other.verifyChecksum == verifyChecksum &&
      other.checksumType == checksumType &&
      other.arch == arch &&
      other.installArgs == installArgs &&
      other.preservePaths.join('\n') == preservePaths.join('\n') &&
      other.preserveFiles.join('\n') == preserveFiles.join('\n');

  @override
  int get hashCode => Object.hash(platform, strategy, nameRegex, checksumRegex,
      verifyChecksum, checksumType, arch, installArgs,
      '${preservePaths.join('\n')}|${preserveFiles.join('\n')}');
}

/// 单个仓库的 Webhook 覆盖配置
class RepoWebhookOverride {

  const RepoWebhookOverride({required this.enabled, this.url});

  factory RepoWebhookOverride.fromJson(Map<String, dynamic> j) => RepoWebhookOverride(
        enabled: j['enabled'] as bool? ?? false,
        url: j['url'] as String?,
      );
  final bool enabled;
  final String? url;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (url != null) 'url': url,
      };
}

/// 仓库配置
class RepoConfig { // Android 模块：Magisk/KernelSU 模块 ID（留空则自动匹配）

  const RepoConfig({
    required this.id,
    required this.owner,
    required this.repo,
    this.tagFilter,
    required this.assetRules,
    this.lastInstalledTag,
    this.notificationsEnabled = true,
    this.webhook,
    this.installDir,
    this.containerName,
    this.dockerRunArgs,
    this.apkInstallMethod,
    this.packageName,
    this.moduleId,
    this.displayName,
    this.fetchApkInfo = true,
    this.apkLabel,
    this.apkIconPath,
    this.checkIntervalMinutes,
    this.lastCheckedAt,
    this.downloadedVersion,
    this.launchFile,
    this.launchCmd,
    this.xposedModule = false,
  });

  factory RepoConfig.fromJson(Map<String, dynamic> j) => RepoConfig(
        id: j['id'] as String? ?? '${j['owner']}/${j['repo']}',
        owner: j['owner'] as String,
        repo: j['repo'] as String,
        tagFilter: j['tagFilter'] as String?,
        assetRules: (j['assetRules'] as List? ?? [])
            .map((e) => AssetRule.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        lastInstalledTag: j['lastInstalledTag'] as String?,
        notificationsEnabled: j['notificationsEnabled'] as bool? ?? true,
        webhook: j['webhook'] == null
            ? null
            : RepoWebhookOverride.fromJson(Map<String, dynamic>.from(j['webhook'])),
        installDir: j['installDir'] as String?,
        containerName: j['containerName'] as String?,
        dockerRunArgs: j['dockerRunArgs'] as String?,
        apkInstallMethod: j['apkInstallMethod'] == null
            ? null
            : InstallMethod.values.firstWhere(
                (e) => e.name == j['apkInstallMethod'],
                orElse: () => InstallMethod.root,
              ),
        packageName: j['packageName'] as String?,
        moduleId: j['moduleId'] as String?,
        displayName: j['displayName'] as String?,
        // 旧配置缺省视为开启（默认打开；显式关闭会写入 false）
        fetchApkInfo: j['fetchApkInfo'] as bool? ?? true,
        apkLabel: j['apkLabel'] as String?,
        apkIconPath: j['apkIconPath'] as String?,
        checkIntervalMinutes: j['checkIntervalMinutes'] as int?,
        lastCheckedAt: j['lastCheckedAt'] as String?,
        downloadedVersion: j['downloadedVersion'] as String?,
        launchFile: j['launchFile'] as String?,
        launchCmd: j['launchCmd'] as String?,
        xposedModule: j['xposedModule'] as bool? ?? false,
      );
  final String id;
  final String owner;
  final String repo;
  final String? tagFilter; // 仅匹配包含该字符串的 tag；null 不过滤
  final List<AssetRule> assetRules;
  final String? lastInstalledTag; // 本地已更新到的版本 tag
  final bool notificationsEnabled;
  final RepoWebhookOverride? webhook;
  final String? installDir; // portable 解压目标目录（Windows/Linux）
  final String? containerName; // docker 容器名（Linux）
  final String? dockerRunArgs; // docker run 的额外参数（Linux，--rm -v ... 等）
  final InstallMethod? apkInstallMethod; // Android APK 安装授权方式（null 用全局默认）
  final String? packageName; // Android APK：已安装应用的包名，用于读取设备上的已装版本
  final String? moduleId;
  final String? displayName; // 自定义显示名称（留空则用自动获取的名称/作者仓库名）
  final bool fetchApkInfo; // Android：下载 APK 后自动读取其图标与软件名称
  final String? apkLabel; // 自动获取到的软件名称
  final String? apkIconPath; // 自动获取到的图标文件（PNG）绝对路径
  final int? checkIntervalMinutes; // 单独设置检测间隔（分钟）；null 用全局设置
  final String? lastCheckedAt; // 上次检测时间（ISO8601，供间隔调度判断）
  final String? downloadedVersion; // 本地已下载 APK 的版本（versionName）
  final String? launchFile; // 桌面端启动文件（相对安装目录，如 app.exe）；为空则卡片不显示「启动」
  final String? launchCmd; // 桌面端启动命令（可选；留空直接启动启动文件）
  final bool xposedModule; // Android APK：声明 xposedmodule 元数据（XP/LSPosed 模块）

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner': owner,
        'repo': repo,
        if (tagFilter != null) 'tagFilter': tagFilter,
        'assetRules': assetRules.map((e) => e.toJson()).toList(),
        if (lastInstalledTag != null) 'lastInstalledTag': lastInstalledTag,
        'notificationsEnabled': notificationsEnabled,
        if (webhook != null) 'webhook': webhook!.toJson(),
        if (installDir != null) 'installDir': installDir,
        if (containerName != null) 'containerName': containerName,
        if (dockerRunArgs != null) 'dockerRunArgs': dockerRunArgs,
        if (apkInstallMethod != null) 'apkInstallMethod': apkInstallMethod!.name,
        if (packageName != null) 'packageName': packageName,
        if (moduleId != null) 'moduleId': moduleId,
        if (displayName != null) 'displayName': displayName,
        if (!fetchApkInfo) 'fetchApkInfo': false, // 默认开启，仅显式关闭时写入
        if (apkLabel != null) 'apkLabel': apkLabel,
        if (apkIconPath != null) 'apkIconPath': apkIconPath,
        if (checkIntervalMinutes != null)
          'checkIntervalMinutes': checkIntervalMinutes,
        if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt,
        if (downloadedVersion != null) 'downloadedVersion': downloadedVersion,
        if (launchFile != null) 'launchFile': launchFile,
        if (launchCmd != null) 'launchCmd': launchCmd,
        if (xposedModule) 'xposedModule': true, // 默认关闭，仅显式开启时写入
      };

  RepoConfig copyWith({
    String? id,
    String? owner,
    String? repo,
    String? tagFilter,
    List<AssetRule>? assetRules,
    String? lastInstalledTag,
    bool? notificationsEnabled,
    RepoWebhookOverride? webhook,
    String? installDir,
    String? containerName,
    String? dockerRunArgs,
    InstallMethod? apkInstallMethod,
    String? packageName,
    String? moduleId,
    String? displayName,
    bool? fetchApkInfo,
    String? apkLabel,
    String? apkIconPath,
    int? checkIntervalMinutes,
    String? lastCheckedAt,
    String? downloadedVersion,
    String? launchFile,
    String? launchCmd,
    bool? xposedModule,
  }) =>
      RepoConfig(
        id: id ?? this.id,
        owner: owner ?? this.owner,
        repo: repo ?? this.repo,
        tagFilter: tagFilter ?? this.tagFilter,
        assetRules: assetRules ?? this.assetRules,
        lastInstalledTag: lastInstalledTag ?? this.lastInstalledTag,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        webhook: webhook ?? this.webhook,
        installDir: installDir ?? this.installDir,
        containerName: containerName ?? this.containerName,
        dockerRunArgs: dockerRunArgs ?? this.dockerRunArgs,
        apkInstallMethod: apkInstallMethod ?? this.apkInstallMethod,
        packageName: packageName ?? this.packageName,
        moduleId: moduleId ?? this.moduleId,
        displayName: displayName ?? this.displayName,
        fetchApkInfo: fetchApkInfo ?? this.fetchApkInfo,
        apkLabel: apkLabel ?? this.apkLabel,
        apkIconPath: apkIconPath ?? this.apkIconPath,
        checkIntervalMinutes: checkIntervalMinutes ?? this.checkIntervalMinutes,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        downloadedVersion: downloadedVersion ?? this.downloadedVersion,
        launchFile: launchFile ?? this.launchFile,
        launchCmd: launchCmd ?? this.launchCmd,
        xposedModule: xposedModule ?? this.xposedModule,
      );

  String get fullName => '$owner/$repo';

  /// 是否为 Android APK 安装类仓库（可获取图标/名称、有安装方式）
  bool get isApkRepo =>
      assetRules.any((r) => r.strategy == UpdateStrategy.apk);

  /// 是否为 Magisk/KernelSU 模块仓库（zip 刷入）
  bool get isMagiskModuleRepo =>
      assetRules.any((r) => r.strategy == UpdateStrategy.module);

  /// 是否为 Xposed/LSPosed 模块仓库（APK 应用且声明了 xposedmodule 元数据）
  bool get isXposedModuleRepo => isApkRepo && xposedModule;

  /// 是否为普通应用（非模块：APK 普通应用 / 桌面 portable/installer/docker）
  bool get isNormalAppRepo => !isMagiskModuleRepo && !isXposedModuleRepo;
}

/// 镜像配置
class MirrorConfig {

  const MirrorConfig({
    required this.name,
    required this.mode,
    required this.pattern,
    required this.replacement,
  });

  factory MirrorConfig.fromJson(Map<String, dynamic> j) => MirrorConfig(
        name: j['name'] as String? ?? 'mirror',
        mode: MirrorMode.values.firstWhere(
          (e) => e.name == (j['mode'] ?? 'prefix'),
          orElse: () => MirrorMode.prefix,
        ),
        pattern: j['pattern'] as String,
        replacement: j['replacement'] as String,
      );
  final String name;
  final MirrorMode mode;
  final String pattern; // prefix 模式：待替换前缀；regex 模式：正则表达式
  final String replacement;

  Map<String, dynamic> toJson() => {
        'name': name,
        'mode': mode.name,
        'pattern': pattern,
        'replacement': replacement,
      };

  MirrorConfig copyWith({
    String? name,
    MirrorMode? mode,
    String? pattern,
    String? replacement,
  }) =>
      MirrorConfig(
        name: name ?? this.name,
        mode: mode ?? this.mode,
        pattern: pattern ?? this.pattern,
        replacement: replacement ?? this.replacement,
      );
}

/// 全局 Webhook 配置
class WebhookConfig {

  const WebhookConfig({
    required this.enabled,
    required this.url,
    required this.events,
    this.headers,
    this.secret,
  });

  factory WebhookConfig.fromJson(Map<String, dynamic> j) => WebhookConfig(
        enabled: j['enabled'] as bool? ?? false,
        url: j['url'] as String? ?? '',
        events: (j['events'] as List? ?? ['updateAvailable', 'updateSuccess', 'updateFailed'])
            .map((e) => NotificationEventX.fromName(e as String))
            .toList(),
        headers: (j['headers'] as Map?)
            ?.map((k, v) => MapEntry(k as String, v as String)),
        secret: j['secret'] as String?,
      );
  final bool enabled;
  final String url;
  final List<NotificationEvent> events;
  final Map<String, String>? headers;
  final String? secret;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'url': url,
        'events': events.map((e) => e.name).toList(),
        if (headers != null) 'headers': headers,
        if (secret != null) 'secret': secret,
      };

  WebhookConfig copyWith({
    bool? enabled,
    String? url,
    List<NotificationEvent>? events,
    Map<String, String>? headers,
    String? secret,
  }) =>
      WebhookConfig(
        enabled: enabled ?? this.enabled,
        url: url ?? this.url,
        events: events ?? this.events,
        headers: headers ?? this.headers,
        secret: secret ?? this.secret,
      );
}

/// 当前配置文件格式版本
///
/// - 1 → 2：新增检测间隔/后台保活（全局）与显示名称、APK 图标名称、仓库级检测间隔
/// - 2 → 4：软件配置与仓库配置拆分为两个文件（config.yaml + repos.yaml），
///   旧版单文件配置在启动时自动检测并转换（原文件备份为 `*.bak`）
const int currentConfigVersion = 4;

/// 全局默认检测间隔（分钟）：6 小时
const int defaultCheckIntervalMinutes = 360;

/// 顶层应用配置
class AppConfig { // Android：签名不一致时仍强制安装（需 root）

  const AppConfig({
    this.configVersion = currentConfigVersion,
    this.githubToken,
    this.mirrors = const [],
    required this.webhook,
    this.systemNotificationsEnabled = true,
    this.downloadDir,
    this.repos = const [],
    this.defaultApkInstallMethod = InstallMethod.root,
    this.loggingEnabled = false,
    this.downloadThreads = 1,
    this.defaultInstallDir,
    this.forceInstallIgnoreSignature = false,
    this.checkIntervalMinutes = defaultCheckIntervalMinutes,
    this.backgroundKeepAlive = false,
  });

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        // 旧版本配置文件没有该字段，按 1 处理
        configVersion: j['configVersion'] as int? ?? 1,
        githubToken: j['githubToken'] as String?,
        mirrors: (j['mirrors'] as List? ?? [])
            .map((e) => MirrorConfig.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        webhook: j['webhook'] == null
            ? const WebhookConfig(
                enabled: false,
                url: '',
                events: NotificationEvent.values,
              )
            : WebhookConfig.fromJson(Map<String, dynamic>.from(j['webhook'])),
        systemNotificationsEnabled: j['systemNotificationsEnabled'] as bool? ?? true,
        downloadDir: j['downloadDir'] as String?,
        repos: (j['repos'] as List? ?? [])
            .map((e) => RepoConfig.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        defaultApkInstallMethod: InstallMethod.values.firstWhere(
          (e) => e.name == (j['defaultApkInstallMethod'] ?? 'root'),
          orElse: () => InstallMethod.root,
        ),
        loggingEnabled: j['loggingEnabled'] as bool? ?? false,
        downloadThreads: j['downloadThreads'] as int? ?? 1,
        defaultInstallDir: j['defaultInstallDir'] as String?,
        forceInstallIgnoreSignature:
            j['forceInstallIgnoreSignature'] as bool? ?? false,
        checkIntervalMinutes: j['checkIntervalMinutes'] as int? ??
            defaultCheckIntervalMinutes,
        backgroundKeepAlive: j['backgroundKeepAlive'] as bool? ?? false,
      );
  final int configVersion; // 配置文件格式版本（便于后续迁移）
  final String? githubToken;
  final List<MirrorConfig> mirrors;
  final WebhookConfig webhook;
  final bool systemNotificationsEnabled;
  final String? downloadDir;
  final List<RepoConfig> repos;
  final InstallMethod defaultApkInstallMethod; // Android APK 静默安装默认授权方式
  final bool loggingEnabled; // 是否记录操作日志到文件
  final int downloadThreads; // 下载线程数（1 = 单线程）
  final String? defaultInstallDir; // 默认文件夹：新建仓库安装目录默认 <默认文件夹>/<作者名>@<repo名>
  final bool forceInstallIgnoreSignature;
  final int checkIntervalMinutes; // 全局自动检测间隔（分钟）；0 = 关闭自动检测
  final bool backgroundKeepAlive; // 后台保活（Android 会同时显示常驻通知）

  Map<String, dynamic> toJson() => {
        'configVersion': configVersion,
        if (githubToken != null) 'githubToken': githubToken,
        'mirrors': mirrors.map((e) => e.toJson()).toList(),
        'webhook': webhook.toJson(),
        'systemNotificationsEnabled': systemNotificationsEnabled,
        if (downloadDir != null) 'downloadDir': downloadDir,
        'repos': repos.map((e) => e.toJson()).toList(),
        'defaultApkInstallMethod': defaultApkInstallMethod.name,
        if (loggingEnabled) 'loggingEnabled': true,
        if (downloadThreads != 1) 'downloadThreads': downloadThreads,
        if (defaultInstallDir != null) 'defaultInstallDir': defaultInstallDir,
        if (forceInstallIgnoreSignature) 'forceInstallIgnoreSignature': true,
        if (checkIntervalMinutes != defaultCheckIntervalMinutes)
          'checkIntervalMinutes': checkIntervalMinutes,
        if (backgroundKeepAlive) 'backgroundKeepAlive': true,
      };

  AppConfig copyWith({
    int? configVersion,
    String? githubToken,
    List<MirrorConfig>? mirrors,
    WebhookConfig? webhook,
    bool? systemNotificationsEnabled,
    String? downloadDir,
    List<RepoConfig>? repos,
    InstallMethod? defaultApkInstallMethod,
    bool? loggingEnabled,
    int? downloadThreads,
    String? defaultInstallDir,
    bool? forceInstallIgnoreSignature,
    int? checkIntervalMinutes,
    bool? backgroundKeepAlive,
  }) =>
      AppConfig(
        configVersion: configVersion ?? this.configVersion,
        githubToken: githubToken ?? this.githubToken,
        mirrors: mirrors ?? this.mirrors,
        webhook: webhook ?? this.webhook,
        systemNotificationsEnabled:
            systemNotificationsEnabled ?? this.systemNotificationsEnabled,
        downloadDir: downloadDir ?? this.downloadDir,
        repos: repos ?? this.repos,
        defaultApkInstallMethod:
            defaultApkInstallMethod ?? this.defaultApkInstallMethod,
        loggingEnabled: loggingEnabled ?? this.loggingEnabled,
        downloadThreads: downloadThreads ?? this.downloadThreads,
        defaultInstallDir: defaultInstallDir ?? this.defaultInstallDir,
        forceInstallIgnoreSignature:
            forceInstallIgnoreSignature ?? this.forceInstallIgnoreSignature,
        checkIntervalMinutes:
            checkIntervalMinutes ?? this.checkIntervalMinutes,
        backgroundKeepAlive: backgroundKeepAlive ?? this.backgroundKeepAlive,
      );
}

/// 简单的 JSON 编解码（避免额外 import 语句散落）
Map<String, dynamic> decodeJson(String s) =>
    jsonDecode(s) as Map<String, dynamic>;

String encodeJson(Object o) => jsonEncode(o);
