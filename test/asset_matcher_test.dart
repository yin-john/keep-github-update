import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/core/github/release_model.dart';
import 'package:github_releases_keep_update/core/matcher/asset_matcher.dart';

Release _release() => const Release(
      tagName: 'v1.0.0',
      name: 'v1.0.0',
      prerelease: false,
      htmlUrl: '',
      assets: [
        Asset(
            name: 'app-windows.zip',
            browserDownloadUrl: 'https://github.com/o/r/releases/download/v1/app-windows.zip',
            size: 1),
        Asset(
            name: 'app-linux.tar.gz',
            browserDownloadUrl: 'https://github.com/o/r/releases/download/v1/app-linux.tar.gz',
            size: 1),
        Asset(
            name: 'module.zip',
            browserDownloadUrl: 'https://github.com/o/r/releases/download/v1/module.zip',
            size: 1),
        Asset(
            name: 'app.apk',
            browserDownloadUrl: 'https://github.com/o/r/releases/download/v1/app.apk',
            size: 1),
      ],
    );

void main() {
  final matcher = AssetMatcher();
  final rules = [
    const AssetRule(
        platform: PlatformType.windows,
        strategy: UpdateStrategy.portable,
        nameRegex: r'.*windows.*\.zip'),
    const AssetRule(
        platform: PlatformType.linux,
        strategy: UpdateStrategy.portable,
        nameRegex: r'.*linux.*\.tar\.gz'),
    const AssetRule(
        platform: PlatformType.android,
        strategy: UpdateStrategy.module,
        nameRegex: r'.*\.zip'),
    const AssetRule(
        platform: PlatformType.android,
        strategy: UpdateStrategy.apk,
        nameRegex: r'.*\.apk'),
  ];

  test('Windows 命中 zip', () {
    final m = matcher.match(_release(), PlatformType.windows, rules);
    expect(m?.asset.name, 'app-windows.zip');
    expect(m?.rule.strategy, UpdateStrategy.portable);
  });

  test('Linux 命中 tar.gz', () {
    final m = matcher.match(_release(), PlatformType.linux, rules);
    expect(m?.asset.name, 'app-linux.tar.gz');
  });

  test('Android apk 优先于 module（按规则顺序）', () {
    final m = matcher.match(_release(), PlatformType.android, rules);
    expect(m?.asset.name, 'module.zip');
  });

  test('按设备架构优先选择对应规则', () {
    const rel = Release(
      tagName: 'v1',
      name: 'v1',
      prerelease: false,
      htmlUrl: '',
      assets: [
        const Asset(
            name: 'app-arm32.apk',
            browserDownloadUrl: 'https://x/app-arm32.apk',
            size: 1),
        const Asset(
            name: 'app-arm64.apk',
            browserDownloadUrl: 'https://x/app-arm64.apk',
            size: 1),
      ],
    );
    final archRules = [
      const AssetRule(
          platform: PlatformType.android,
          strategy: UpdateStrategy.apk,
          nameRegex: r'.*\.apk$',
          arch: TargetArch.arm32),
      const AssetRule(
          platform: PlatformType.android,
          strategy: UpdateStrategy.apk,
          nameRegex: r'.*\.apk$',
          arch: TargetArch.arm64),
    ];
    final m64 = matcher.match(rel, PlatformType.android, archRules, TargetArch.arm64);
    expect(m64?.asset.name, 'app-arm64.apk');
    final m32 = matcher.match(rel, PlatformType.android, archRules, TargetArch.arm32);
    expect(m32?.asset.name, 'app-arm32.apk');
  });
}
