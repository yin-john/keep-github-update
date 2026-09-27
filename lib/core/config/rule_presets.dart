/// 系统预设规则库：按平台（系统）分组，供 GUI 快速添加匹配规则。
library;

import 'models.dart';

/// 一条预设规则
class RulePreset { // 预填规则
  const RulePreset({
    required this.name,
    required this.description,
    required this.rule,
  });
  final String name; // 预设名称（按钮显示）
  final String description; // 说明（悬停提示）
  final AssetRule rule;
}

/// 三大系统（Windows / Linux / Android）的预设规则
const Map<PlatformType, List<RulePreset>> systemRulePresets = {
  PlatformType.windows: [
    RulePreset(
      name: 'Portable 压缩包',
      description:
          '匹配 zip / 7z / tar.gz / tar.xz 等压缩包，解压覆盖到安装目录',
      rule: AssetRule(
        platform: PlatformType.windows,
        strategy: UpdateStrategy.portable,
        // Dart RegExp 不支持 (?i) 内联标志，用字符类兼容大小写
        nameRegex: r'.*\.([Zz][Ii][Pp]|7[Zz]|[Tt][Aa][Rr]'
            r'(\.([Gg][Zz]|[Bb][Zz]2|[Xx][Zz]|[Zz][Ss][Tt]))?'
            r'|[Tt][Gg][Zz]|[Gg][Zz]|[Bb][Zz]2|[Xx][Zz])$',
      ),
    ),
    RulePreset(
      name: 'Portable EXE（单文件）',
      description:
          '匹配单个 .exe（排除 setup），不解压，直接下载覆盖到安装目录（如 yt-dlp.exe）',
      rule: AssetRule(
        platform: PlatformType.windows,
        strategy: UpdateStrategy.portable,
        nameRegex: r'^(?!.*[Ss]etup).*\.exe$',
      ),
    ),
    RulePreset(
      name: 'Installer (MSI/EXE)',
      description: '匹配 .msi 或 setup*.exe，静默安装',
      rule: AssetRule(
        platform: PlatformType.windows,
        strategy: UpdateStrategy.installer,
        nameRegex: r'.*(\.msi|setup.*\.exe)$',
      ),
    ),
  ],
  PlatformType.linux: [
    RulePreset(
      name: 'Portable 压缩包',
      description:
          '匹配 tar.gz / tar.xz / zip 等压缩包，解压覆盖到安装目录',
      rule: AssetRule(
        platform: PlatformType.linux,
        strategy: UpdateStrategy.portable,
        nameRegex: r'.*\.([Zz][Ii][Pp]|7[Zz]|[Tt][Aa][Rr]'
            r'(\.([Gg][Zz]|[Bb][Zz]2|[Xx][Zz]|[Zz][Ss][Tt]))?'
            r'|[Tt][Gg][Zz]|[Gg][Zz]|[Bb][Zz]2|[Xx][Zz])$',
      ),
    ),
    RulePreset(
      name: 'Portable AppImage',
      description: '匹配 .AppImage',
      rule: AssetRule(
        platform: PlatformType.linux,
        strategy: UpdateStrategy.portable,
        nameRegex: r'.*\.AppImage$',
      ),
    ),
    RulePreset(
      name: 'Docker',
      description: '拉取镜像并重建容器（需填写容器名）',
      rule: AssetRule(
        platform: PlatformType.linux,
        strategy: UpdateStrategy.docker,
        nameRegex: r'.*',
      ),
    ),
  ],
  PlatformType.android: [
    RulePreset(
      name: 'APK (ARM64)',
      description: '匹配 arm64-v8a 的 .apk',
      rule: AssetRule(
        platform: PlatformType.android,
        strategy: UpdateStrategy.apk,
        nameRegex: r'.*arm64.*\.apk$',
        arch: TargetArch.arm64,
      ),
    ),
    RulePreset(
      name: 'APK (ARM32)',
      description: '匹配 armeabi-v7a 的 .apk',
      rule: AssetRule(
        platform: PlatformType.android,
        strategy: UpdateStrategy.apk,
        nameRegex: r'.*(arm32|armv7|armeabi).*\.apk$',
        arch: TargetArch.arm32,
      ),
    ),
    RulePreset(
      name: 'Magisk/KernelSU 模块',
      description: '匹配模块 .zip',
      rule: AssetRule(
        platform: PlatformType.android,
        strategy: UpdateStrategy.module,
        nameRegex: r'.*\.zip$',
      ),
    ),
  ],
};
