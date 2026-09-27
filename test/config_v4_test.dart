/// 配置格式 v4：软件配置与仓库配置拆分、向上兼容与启动自动迁移。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/config_repository.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:path/path.dart' as p;

import 'support/fs.dart';

const _rule = AssetRule(
  platform: PlatformType.windows,
  strategy: UpdateStrategy.portable,
  nameRegex: r'.*\.zip$',
);

RepoConfig _repo() => const RepoConfig(
      id: 'o/r',
      owner: 'o',
      repo: 'r',
      assetRules: [_rule],
      displayName: '我的工具',
      apkLabel: '示例应用',
      downloadedVersion: '1.2.3',
      checkIntervalMinutes: 15,
      lastCheckedAt: '2026-01-01T12:00:00.000',
    );

AppConfig _cfg() => AppConfig(
      webhook: const WebhookConfig(enabled: false, url: '', events: []),
      repos: [_repo()],
    );

void main() {
  test('当前格式版本为 4', () => expect(currentConfigVersion, 4));

  test('v1 旧配置加载后自动补齐新字段', () {
    final cfg = AppConfig.fromJson({
      'configVersion': 1,
      'webhook': {'enabled': false, 'url': '', 'events': []},
      'repos': [
        {
          'id': 'o/r',
          'owner': 'o',
          'repo': 'r',
          'assetRules': [
            {'platform': 'windows', 'strategy': 'portable', 'nameRegex': '.*'}
          ],
        }
      ],
    });
    expect(cfg.checkIntervalMinutes, defaultCheckIntervalMinutes);
    expect(cfg.backgroundKeepAlive, isFalse);
    expect(cfg.repos.single.downloadedVersion, isNull);
  });

  test('downloadedVersion 序列化往返', () {
    final back = RepoConfig.fromJson(_repo().toJson());
    expect(back.downloadedVersion, '1.2.3');
    expect(back.apkLabel, '示例应用');
  });

  test('旧版单文件配置启动时自动拆分并转换', () async {
    final dir = await Directory.systemTemp.createTemp('grku_mig_');
    addTearDown(() => deleteDirQuietly(dir));
    final repo = ConfigRepository(p.join(dir.path, 'config.yaml'));
    await File(p.join(dir.path, 'config.yaml')).writeAsString(
        'configVersion: 2\nsystemNotificationsEnabled: true\n'
        'checkIntervalMinutes: 30\nbackgroundKeepAlive: true\n'
        'repos:\n  - id: o/r\n    owner: o\n    repo: r\n'
        '    assetRules:\n      - platform: windows\n'
        '        strategy: portable\n        nameRegex: ".*\\\\.zip\$"\n');

    final cfg = await repo.load();

    expect(cfg.configVersion, currentConfigVersion);
    expect(cfg.checkIntervalMinutes, 30);
    expect(cfg.backgroundKeepAlive, isTrue);
    expect(cfg.repos.single.fullName, 'o/r');
    expect(File(p.join(dir.path, 'repos.yaml')).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'config.yaml.bak')).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'config.yaml')).readAsStringSync(),
        isNot(contains('repos:')));
    // 重复加载稳定（不重复迁移）
    expect((await repo.load()).repos.single.fullName, 'o/r');
  });

  test('保存后 config.yaml 不含仓库、repos.yaml 含仓库', () async {
    final dir = await Directory.systemTemp.createTemp('grku_split_');
    addTearDown(() => deleteDirQuietly(dir));
    final repo = ConfigRepository(p.join(dir.path, 'config.yaml'));
    await repo.save(_cfg());

    final appText = File(p.join(dir.path, 'config.yaml')).readAsStringSync();
    expect(appText, contains('configVersion: $currentConfigVersion'));
    expect(appText, isNot(contains('repos:')));
    final reposText = File(p.join(dir.path, 'repos.yaml')).readAsStringSync();
    expect(reposText, contains('downloadedVersion'));
    expect((await repo.load()).repos.single.downloadedVersion, '1.2.3');
  });

  test('导出为单个合并文件（含软件配置与仓库）', () async {
    final dir = await Directory.systemTemp.createTemp('grku_exp_');
    addTearDown(() => deleteDirQuietly(dir));
    final repo = ConfigRepository(p.join(dir.path, 'config.yaml'));
    await repo.save(_cfg());

    final out = p.join(dir.path, 'export.yaml');
    await repo.export(out);

    final text = File(out).readAsStringSync();
    expect(text, contains('configVersion: $currentConfigVersion'));
    expect(text, contains('repos:'));
    expect(text, contains('displayName'));
    final imported = await repo.import(out);
    expect(imported.repos.single.displayName, '我的工具');
    expect(imported.repos.single.downloadedVersion, '1.2.3');
  });
}
