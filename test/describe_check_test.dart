import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/core/github/release_model.dart';
import 'package:github_releases_keep_update/core/matcher/asset_matcher.dart';
import 'package:github_releases_keep_update/core/updater/update_service.dart';
import 'package:github_releases_keep_update/core/version/installed_version.dart';

RepoConfig _repo(String? installed) => RepoConfig(
      id: 'o/r',
      owner: 'o',
      repo: 'r',
      lastInstalledTag: installed,
      assetRules: const [
        AssetRule(
            platform: PlatformType.windows,
            strategy: UpdateStrategy.portable,
            nameRegex: r'.*\.zip$'),
      ],
    );

Release _rel(String tag) => Release(
      tagName: tag,
      name: tag,
      prerelease: false,
      htmlUrl: '',
      assets: const [
        Asset(name: 'a.zip', browserDownloadUrl: 'https://x/a.zip', size: 1),
      ],
    );

/// [installed] 模拟服务从设备上解析出的真实已装版本（默认同 lastInstalledTag）
UpdateCheck _check(
  RepoConfig r,
  String tag, {
  bool matched = true,
  String? installed,
  bool useInstalled = true,
}) {
  final rel = _rel(tag);
  final inst = useInstalled ? (installed ?? r.lastInstalledTag) : null;
  final hasUpdate = matched &&
      (inst != null && inst.isNotEmpty
          ? !versionMatches(inst, tag)
          : tag != r.lastInstalledTag);
  return UpdateCheck(
    repo: r,
    release: rel,
    match: matched ? MatchResult(rel.assets.first, r.assetRules.first) : null,
    hasUpdate: hasUpdate,
    installedVersion: inst,
  );
}

void main() {
  test('无匹配资产时不是「已是最新」', () {
    expect(describeCheck(_check(_repo(null), 'v1', matched: false)),
        '未找到匹配的资产');
  });

  test('未安装且匹配到资产 → 未安装可更新', () {
    expect(describeCheck(_check(_repo(null), 'v1')), contains('未安装'));
  });

  test('已安装旧版本 → 可更新，并显示已装版本', () {
    final s = describeCheck(_check(_repo('v0'), 'v1'));
    expect(s, contains('可更新'));
    expect(s, contains('v0'));
  });

  test('已安装相同版本 → 已是最新', () {
    expect(describeCheck(_check(_repo('v1'), 'v1')), contains('已是最新'));
  });

  test('设备读取到的版本（无 v 前缀）与 tag 视为同一版本', () {
    // 模块版本是 1.2.3，release tag 是 v1.2.3
    final c = _check(_repo(null), 'v1.2.3', installed: '1.2.3');
    expect(c.hasUpdate, isFalse);
    expect(describeCheck(c), contains('已是最新'));
    expect(describeCheck(c), contains('1.2.3'));
  });

  test('设备读取到旧版本 → 可更新', () {
    final c = _check(_repo(null), 'v2.0.0', installed: '1.9.0');
    expect(c.hasUpdate, isTrue);
    expect(describeCheck(c), contains('可更新'));
  });

  test('读取不到设备版本时回退到配置记录的 tag', () {
    final c = _check(_repo('v1'), 'v1', useInstalled: false);
    expect(c.hasUpdate, isFalse);
    expect(describeCheck(c), contains('未安装'));
  });
}
