import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/config_repository.dart';
import 'package:github_releases_keep_update/core/config/models.dart';

AppConfig _cfg({List<RepoConfig> repos = const []}) => AppConfig(
      webhook: const WebhookConfig(enabled: false, url: '', events: []),
      repos: repos,
    );

const RepoConfig _androidRepo = RepoConfig(
  id: 'a/b',
  owner: 'a',
  repo: 'b',
  assetRules: [
    AssetRule(
      platform: PlatformType.android,
      strategy: UpdateStrategy.apk,
      nameRegex: r'.*\.apk$',
    ),
  ],
  packageName: 'com.example.app',
  moduleId: 'my_module',
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('grku_export_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('保存的配置带版本号与 Android 字段', () async {
    final path = '${dir.path}/config.yaml';
    await ConfigRepository(path).save(_cfg(repos: const [_androidRepo]));

    final text = File(path).readAsStringSync();
    expect(text, contains('configVersion: 1'));
    // YAML 写出时字符串会带引号，这里只校验字段名与取值
    expect(text, contains('packageName'));
    expect(text, contains('com.example.app'));
    expect(text, contains('moduleId'));
    expect(text, contains('my_module'));

    final back = await ConfigRepository(path).load();
    expect(back.configVersion, currentConfigVersion);
    expect(back.repos.single.packageName, 'com.example.app');
    expect(back.repos.single.moduleId, 'my_module');
  });

  test('旧版配置（无版本号）按 1 处理，可正常加载', () async {
    final path = '${dir.path}/old.yaml';
    File(path).writeAsStringSync(
        'webhook:\n  enabled: false\n  url: ""\n  events: []\nrepos: []\n');
    final cfg = await ConfigRepository(path).load();
    expect(cfg.configVersion, 1);
    expect(cfg.repos, isEmpty);
  });

  test('导出配置文件后可再次导入（写盘 + 读取）', () async {
    final mainPath = '${dir.path}/config.yaml';
    final outPath = '${dir.path}/export.json';
    final cfg = _cfg(repos: const [_androidRepo]).copyWith(
      forceInstallIgnoreSignature: true,
      downloadDir: '/tmp/dl',
    );
    await ConfigRepository(mainPath).save(cfg);

    final repo = ConfigRepository(mainPath);
    await repo.export(outPath);
    expect(File(outPath).existsSync(), isTrue);
    expect(File(outPath).lengthSync(), greaterThan(0));

    final imported = await repo.import(outPath);
    expect(imported.forceInstallIgnoreSignature, isTrue);
    expect(imported.downloadDir, '/tmp/dl');
    expect(imported.configVersion, currentConfigVersion);
    expect(imported.repos.single.packageName, 'com.example.app');
  });

  test('写入配置会自动创建父目录', () async {
    final path = '${dir.path}/nested/deep/config.yaml';
    await ConfigRepository(path).save(_cfg());
    expect(File(path).existsSync(), isTrue);
  });

  test('导入空路径 / 空文件 / 不存在的文件都不会清空现有配置', () async {
    final mainPath = '${dir.path}/config.yaml';
    final repo = ConfigRepository(mainPath);
    await repo.save(_cfg(repos: const [_androidRepo]));

    final blank = File('${dir.path}/blank.yaml')..writeAsStringSync('   \n\n');

    for (final bad in ['', '   ', '${dir.path}/missing.yaml', blank.path]) {
      await expectLater(repo.import(bad), throwsA(isA<ConfigException>()));
    }

    // 现有配置必须完好无损
    final still = await ConfigRepository(mainPath).load();
    expect(still.repos.length, 1);
    expect(still.repos.single.packageName, 'com.example.app');
  });

  test('导入不含仓库的配置默认被拒，显式允许后才生效', () async {
    final mainPath = '${dir.path}/config.yaml';
    final repo = ConfigRepository(mainPath);
    await repo.save(_cfg(repos: const [_androidRepo]));

    final emptyCfg = '${dir.path}/no_repos.yaml';
    File(emptyCfg).writeAsStringSync(
        'configVersion: 1\nwebhook:\n  enabled: false\n  url: ""\n  events: []\nrepos: []\n');

    await expectLater(repo.import(emptyCfg), throwsA(isA<ConfigException>()));
    expect((await ConfigRepository(mainPath).load()).repos.length, 1);

    final applied = await repo.import(emptyCfg, allowEmpty: true);
    expect(applied.repos, isEmpty);
    expect((await ConfigRepository(mainPath).load()).repos, isEmpty);
  });

  test('导出：空路径与目录路径被拒绝，无扩展名自动补 .yaml', () async {
    final mainPath = '${dir.path}/config.yaml';
    final repo = ConfigRepository(mainPath);
    await repo.save(_cfg(repos: const [_androidRepo]));

    await expectLater(repo.export(''), throwsA(isA<ConfigException>()));
    await expectLater(repo.export('   '), throwsA(isA<ConfigException>()));
    await expectLater(repo.export(dir.path), throwsA(isA<ConfigException>()));

    final written = await repo.export('${dir.path}/plain');
    expect(written.endsWith('.yaml'), isTrue);
    expect(File(written).existsSync(), isTrue);
  });

  test('导入时未写扩展名会自动匹配同名 .yaml', () async {
    final mainPath = '${dir.path}/config.yaml';
    final repo = ConfigRepository(mainPath);
    await repo.save(_cfg(repos: const [_androidRepo]));

    await repo.export('${dir.path}/exported'); // 实际生成 exported.yaml
    final back = await repo.import('${dir.path}/exported');
    expect(back.repos.length, 1);
    expect(back.repos.single.packageName, 'com.example.app');
  });
}
