/// 配置格式 v2：显示名称、APK 图标/名称、检测间隔、后台保活的序列化与兼容性。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';

const _rule = AssetRule(
  platform: PlatformType.windows,
  strategy: UpdateStrategy.portable,
  nameRegex: r'.*\.zip$',
);

void main() {
  group('配置文件版本', () {
    test('当前格式版本为 2', () {
      expect(currentConfigVersion, 2);
    });

    test('v1 旧配置加载后自动补齐 v2 字段', () {
      // 模拟旧版本配置文件（没有新增字段）
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
      expect(cfg.repos.single.displayName, isNull);
      expect(cfg.repos.single.fetchApkInfo, isFalse);
      expect(cfg.repos.single.apkLabel, isNull);
      expect(cfg.repos.single.apkIconPath, isNull);
      expect(cfg.repos.single.checkIntervalMinutes, isNull);
      expect(cfg.repos.single.lastCheckedAt, isNull);
    });

    test('保存时写入 v2 版本号', () {
      const cfg = AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: []),
      );
      expect(cfg.toJson()['configVersion'], 2);
    });
  });

  group('全局新字段', () {
    test('检测间隔与后台保活往返', () {
      const cfg = AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: []),
        checkIntervalMinutes: 30,
        backgroundKeepAlive: true,
      );
      final back = AppConfig.fromJson(cfg.toJson());
      expect(back.checkIntervalMinutes, 30);
      expect(back.backgroundKeepAlive, isTrue);
    });

    test('默认值：6 小时、不保活，且默认值不写入文件', () {
      const cfg = AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: []),
      );
      expect(cfg.checkIntervalMinutes, defaultCheckIntervalMinutes);
      expect(cfg.backgroundKeepAlive, isFalse);
      final json = cfg.toJson();
      expect(json.containsKey('checkIntervalMinutes'), isFalse);
      expect(json.containsKey('backgroundKeepAlive'), isFalse);
    });

    test('关闭自动检测（0）能正确保存与读回', () {
      const cfg = AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: []),
        checkIntervalMinutes: 0,
      );
      expect(AppConfig.fromJson(cfg.toJson()).checkIntervalMinutes, 0);
    });
  });

  group('仓库新字段', () {
    test('显示名称 / APK 信息 / 检测间隔 / 检测时间往返', () {
      const r = RepoConfig(
        id: 'o/r',
        owner: 'o',
        repo: 'r',
        assetRules: [_rule],
        displayName: '我的工具',
        fetchApkInfo: true,
        apkLabel: '示例应用',
        apkIconPath: '/data/user/0/pkg/files/grku_icons/com.foo.png',
        checkIntervalMinutes: 15,
        lastCheckedAt: '2026-01-01T12:00:00.000',
      );
      final back = RepoConfig.fromJson(r.toJson());
      expect(back.displayName, '我的工具');
      expect(back.fetchApkInfo, isTrue);
      expect(back.apkLabel, '示例应用');
      expect(back.apkIconPath, r.apkIconPath);
      expect(back.checkIntervalMinutes, 15);
      expect(back.lastCheckedAt, '2026-01-01T12:00:00.000');
    });

    test('未设置时不写入文件', () {
      const r = RepoConfig(
          id: 'o/r', owner: 'o', repo: 'r', assetRules: [_rule]);
      final json = r.toJson();
      expect(json.containsKey('displayName'), isFalse);
      expect(json.containsKey('fetchApkInfo'), isFalse);
      expect(json.containsKey('checkIntervalMinutes'), isFalse);
      expect(json.containsKey('lastCheckedAt'), isFalse);
    });

    test('copyWith 能更新新字段且不影响其它字段', () {
      const r = RepoConfig(
          id: 'o/r', owner: 'o', repo: 'r', assetRules: [_rule]);
      final updated = r.copyWith(
        displayName: '名称',
        apkLabel: '标签',
        fetchApkInfo: true,
        checkIntervalMinutes: 60,
        lastCheckedAt: '2026-01-01T00:00:00.000',
      );
      expect(updated.displayName, '名称');
      expect(updated.apkLabel, '标签');
      expect(updated.fetchApkInfo, isTrue);
      expect(updated.checkIntervalMinutes, 60);
      expect(updated.lastCheckedAt, '2026-01-01T00:00:00.000');
      expect(updated.fullName, 'o/r');
      expect(updated.assetRules, [_rule]);
    });

    test('isApkRepo 仅在含 APK 策略时为真', () {
      const apk = RepoConfig(
        id: 'o/r',
        owner: 'o',
        repo: 'r',
        assetRules: [
          AssetRule(
              platform: PlatformType.android,
              strategy: UpdateStrategy.apk,
              nameRegex: r'.*\.apk$'),
        ],
      );
      expect(apk.isApkRepo, isTrue);
      const portable = RepoConfig(
          id: 'o/r', owner: 'o', repo: 'r', assetRules: [_rule]);
      expect(portable.isApkRepo, isFalse);
    });
  });
}
