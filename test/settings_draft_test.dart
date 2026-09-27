/// 设置页草稿机制：未保存前修改只停留在草稿，提交时保留最新仓库列表。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/core/config/settings_draft.dart';

const _rule = AssetRule(
  platform: PlatformType.windows,
  strategy: UpdateStrategy.portable,
  nameRegex: r'.*\.zip$',
);

RepoConfig _repo(String id) => RepoConfig(
      id: id,
      owner: 'o',
      repo: id,
      assetRules: const [_rule],
    );

AppConfig _base() => const AppConfig(
      webhook: WebhookConfig(enabled: false, url: '', events: []),
      githubToken: 'old-token',
      mirrors: [],
      systemNotificationsEnabled: true,
      downloadThreads: 1,
      checkIntervalMinutes: 360,
      loggingEnabled: false,
    );

void main() {
  group('SettingsDraft 初始状态', () {
    test('初始草稿等于基准配置，且不标记为脏', () {
      final base = _base();
      final draft = SettingsDraft(base);
      expect(draft.dirty, isFalse);
      expect(draft.value.githubToken, 'old-token');
      expect(draft.value.checkIntervalMinutes, 360);
    });
  });

  group('SettingsDraft.patch', () {
    test('修改只作用于草稿，并标记为脏', () {
      final draft = SettingsDraft(_base());
      draft.patch((b) => b.copyWith(
            checkIntervalMinutes: 60,
            systemNotificationsEnabled: false,
          ));
      expect(draft.dirty, isTrue);
      expect(draft.value.checkIntervalMinutes, 60);
      expect(draft.value.systemNotificationsEnabled, isFalse);
      // 未涉及的字段保持不变
      expect(draft.value.githubToken, 'old-token');
    });

    test('连续多次修改累积生效', () {
      final draft = SettingsDraft(_base());
      draft.patch((b) => b.copyWith(downloadThreads: 4));
      draft.patch((b) => b.copyWith(loggingEnabled: true));
      expect(draft.value.downloadThreads, 4);
      expect(draft.value.loggingEnabled, isTrue);
      expect(draft.dirty, isTrue);
    });

    test('镜像增删改通过 patch 生效', () {
      final draft = SettingsDraft(_base());
      const m0 = MirrorConfig(
          name: 'ghproxy',
          mode: MirrorMode.prefix,
          pattern: 'https://github.com',
          replacement: 'https://mirror.example.com');
      draft.patch((b) => b.copyWith(mirrors: [...b.mirrors, m0]));
      expect(draft.value.mirrors.length, 1);
      draft.patch((b) {
        final ms = [...b.mirrors];
        ms[0] = ms[0].copyWith(name: 'renamed');
        return b.copyWith(mirrors: ms);
      });
      expect(draft.value.mirrors.single.name, 'renamed');
      draft.patch((b) => b.copyWith(mirrors: [...b.mirrors]..removeAt(0)));
      expect(draft.value.mirrors, isEmpty);
    });
  });

  group('SettingsDraft.reset', () {
    test('reset 丢弃草稿并清除脏标记', () {
      final draft = SettingsDraft(_base());
      draft.patch((b) => b.copyWith(checkIntervalMinutes: 10));
      expect(draft.dirty, isTrue);
      final fresh = _base().copyWith(githubToken: 'new-token');
      draft.reset(fresh);
      expect(draft.dirty, isFalse);
      expect(draft.value.githubToken, 'new-token');
      expect(draft.value.checkIntervalMinutes, 360);
    });
  });

  group('SettingsDraft.commitTo', () {
    test('提交保留 latest 的 repos，软件设置取草稿', () {
      final base = _base();
      final draft = SettingsDraft(base);
      draft.patch((b) => b.copyWith(
            checkIntervalMinutes: 30,
            githubToken: 'token-from-draft',
          ));

      // 模拟设置页停留期间仓库列表在别处被修改（provider 最新值）
      final latest = base.copyWith(repos: [_repo('a'), _repo('b')]);

      final committed = draft.commitTo(latest);
      expect(committed.repos.length, 2);
      expect(committed.repos.map((r) => r.id), ['a', 'b']);
      expect(committed.checkIntervalMinutes, 30);
      expect(committed.githubToken, 'token-from-draft');
    });

    test('草稿未修改的设置字段以草稿基准值为准', () {
      final base = _base();
      final draft = SettingsDraft(base);
      draft.patch((b) => b.copyWith(downloadThreads: 8));
      // latest 的 webhook 与草稿不同：草稿未改 webhook，应保持草稿值
      final latest = base.copyWith(
        webhook: const WebhookConfig(enabled: true, url: 'https://x', events: []),
      );
      final committed = draft.commitTo(latest);
      expect(committed.downloadThreads, 8);
      // 草稿基于 base，其 webhook 仍是 base 的值（enabled=false）
      expect(committed.webhook.enabled, isFalse);
    });
  });
}
