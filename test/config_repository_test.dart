import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/config_repository.dart';
import 'package:github_releases_keep_update/core/config/models.dart';

AppConfig _sample() => const AppConfig(
      githubToken: 'token123',
      mirrors: [
        MirrorConfig(
            name: 'ghproxy',
            mode: MirrorMode.prefix,
            pattern: 'https://github.com',
            replacement: 'https://ghproxy.com/https://github.com'),
      ],
      webhook: WebhookConfig(
          enabled: true,
          url: 'https://hook.example.com',
          events: [NotificationEvent.updateAvailable, NotificationEvent.updateSuccess]),
      systemNotificationsEnabled: true,
      repos: [
        RepoConfig(
          id: 'o/r',
          owner: 'o',
          repo: 'r',
          assetRules: [
            AssetRule(
                platform: PlatformType.windows,
                strategy: UpdateStrategy.portable,
                nameRegex: r'.*windows.*\.zip'),
          ],
          lastInstalledTag: 'v1.0.0',
        ),
      ],
    );

void main() {
  test('YAML 导入导出往返一致', () async {
    final dir = await Directory.systemTemp.createTemp();
    final path = '${dir.path}/cfg.yaml';
    final repo = ConfigRepository(path);
    await repo.save(_sample());
    final loaded = await repo.load();
    expect(loaded.githubToken, 'token123');
    expect(loaded.mirrors.length, 1);
    expect(loaded.repos.first.lastInstalledTag, 'v1.0.0');
    expect(loaded.webhook.url, 'https://hook.example.com');
    await dir.delete(recursive: true);
  });

  test('JSON 导入导出往返一致', () async {
    final dir = await Directory.systemTemp.createTemp();
    final path = '${dir.path}/cfg.json';
    final repo = ConfigRepository(path);
    await repo.save(_sample());
    final loaded = await repo.load();
    expect(loaded.repos.length, 1);
    expect(loaded.webhook.events.length, 2);
    await dir.delete(recursive: true);
  });

  test('validate 捕获非法正则与空规则', () async {
    const bad = AppConfig(
      webhook: const WebhookConfig(enabled: false, url: '', events: []),
      repos: [
        const RepoConfig(
          id: 'x/y',
          owner: 'x',
          repo: 'y',
          assetRules: [
            AssetRule(
                platform: PlatformType.windows,
                strategy: UpdateStrategy.portable,
                nameRegex: r'('),
          ],
        ),
      ],
    );
    final errors = ConfigRepository('x').validate(bad);
    expect(errors.any((e) => e.contains('正则')), isTrue);
  });
}
