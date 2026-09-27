import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/app_paths.dart';
import 'package:github_releases_keep_update/core/config/config_repository.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/ui/providers/app_providers.dart';

RepoConfig _repo(String owner, String name) => RepoConfig(
      id: '$owner/$name',
      owner: owner,
      repo: name,
      assetRules: const [
        AssetRule(
            platform: PlatformType.windows,
            strategy: UpdateStrategy.portable,
            nameRegex: r'.*\.zip$'),
      ],
    );

void main() {
  late Directory tmp;
  late String cfgPath;
  late ProviderContainer container;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grku_test_');
    cfgPath = '${tmp.path}/config.yaml';
    container = ProviderContainer(overrides: [
      configRepoProvider.overrideWithValue(ConfigRepository(cfgPath)),
    ]);
  });

  tearDown(() {
    container.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('添加仓库：更新状态并写入文件', () async {
    final notifier = container.read(configProvider.notifier);
    await notifier.ready; // 等初始加载完成，避免被覆盖
    notifier.addRepo(_repo('a', 'b'));
    expect(container.read(configProvider).repos.single.fullName, 'a/b');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final saved = await ConfigRepository(cfgPath).load();
    expect(saved.repos.single.fullName, 'a/b');
  });

  test('更新仓库：替换对应项', () async {
    final notifier = container.read(configProvider.notifier);
    await notifier.ready;
    notifier.addRepo(_repo('a', 'b'));
    notifier.updateRepo(_repo('a', 'b').copyWith(lastInstalledTag: 'v1'));
    expect(
        container.read(configProvider).repos.single.lastInstalledTag, 'v1');
  });

  test('删除仓库：移除配置、写入文件并清理下载目录', () async {
    final notifier = container.read(configProvider.notifier);
    await notifier.ready;
    // 用临时目录作为下载基准，避免触碰真实目录
    final base = Directory('${tmp.path}/dl')..createSync(recursive: true);
    notifier
        .setConfig(container.read(configProvider).copyWith(downloadDir: base.path));
    notifier.addRepo(_repo('a', 'b'));

    final repoDir = Directory(repoDownloadDir('a', 'b', baseDir: base.path));
    repoDir.createSync(recursive: true);
    File('${repoDir.path}/x.zip').writeAsStringSync('x');
    expect(repoDir.existsSync(), isTrue);

    await notifier.removeRepo('a/b');
    expect(container.read(configProvider).repos, isEmpty);
    expect(repoDir.existsSync(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final saved = await ConfigRepository(cfgPath).load();
    expect(saved.repos, isEmpty);
  });

  test('删除不存在的仓库：不报错', () async {
    final notifier = container.read(configProvider.notifier);
    await notifier.ready;
    await notifier.removeRepo('no/such');
    expect(container.read(configProvider).repos, isEmpty);
  });
}
