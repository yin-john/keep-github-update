import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';

void main() {
  group('AssetRule', () {
    test('按值相等', () {
      const a = AssetRule(
          platform: PlatformType.windows,
          strategy: UpdateStrategy.portable,
          nameRegex: r'.*\.zip$');
      const b = AssetRule(
          platform: PlatformType.windows,
          strategy: UpdateStrategy.portable,
          nameRegex: r'.*\.zip$');
      const c = AssetRule(
          platform: PlatformType.linux,
          strategy: UpdateStrategy.portable,
          nameRegex: r'.*\.zip$');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('preservePaths / preserveFiles / installArgs 序列化往返', () {
      const r = AssetRule(
        platform: PlatformType.windows,
        strategy: UpdateStrategy.portable,
        nameRegex: r'.*\.zip$',
        preservePaths: ['^data/', 'config'],
        preserveFiles: [r'^config\.json$', r'\.ini$'],
        installArgs: 'ALLUSERS=1',
      );
      final back = AssetRule.fromJson(r.toJson());
      expect(back.preservePaths, ['^data/', 'config']);
      expect(back.preserveFiles, [r'^config\.json$', r'\.ini$']);
      expect(back.installArgs, 'ALLUSERS=1');
      expect(back, equals(r));
      // 解压时目录与文件规则合并使用
      expect(back.allPreservePaths,
          ['^data/', 'config', r'^config\.json$', r'\.ini$']);
    });

    test('数据文件规则只保留匹配的文件', () {
      const r = AssetRule(
        platform: PlatformType.windows,
        strategy: UpdateStrategy.portable,
        nameRegex: r'.*\.zip$',
        preserveFiles: [r'^config\.json$'],
      );
      expect(r.preservePaths, isEmpty);
      expect(r.allPreservePaths, [r'^config\.json$']);
    });
  });

  group('AppConfig', () {
    test('loggingEnabled 序列化往返', () {
      const cfg = AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: []),
        loggingEnabled: true,
      );
      final back = AppConfig.fromJson(cfg.toJson());
      expect(back.loggingEnabled, isTrue);
    });

    test('默认不记录日志', () {
      const cfg = AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: []),
      );
      expect(cfg.loggingEnabled, isFalse);
    });

    test('defaultInstallDir 序列化往返', () {
      const cfg = AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: []),
        defaultInstallDir: r'D:\Apps',
      );
      expect(AppConfig.fromJson(cfg.toJson()).defaultInstallDir, r'D:\Apps');
    });

    test('downloadThreads 序列化往返', () {
      const cfg = AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: []),
        downloadThreads: 4,
      );
      expect(AppConfig.fromJson(cfg.toJson()).downloadThreads, 4);
      const def = AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: []),
      );
      expect(def.downloadThreads, 1);
    });
  });

  group('平台策略映射', () {
    test('Windows 不含 docker/模块/APK', () {
      final s = PlatformType.windows.strategies;
      expect(s, contains(UpdateStrategy.portable));
      expect(s, contains(UpdateStrategy.installer));
      expect(s, isNot(contains(UpdateStrategy.docker)));
      expect(s, isNot(contains(UpdateStrategy.apk)));
      expect(s, isNot(contains(UpdateStrategy.module)));
    });

    test('仅 Android 使用 APK 授权方式', () {
      expect(PlatformType.android.usesApkInstallMethod, isTrue);
      expect(PlatformType.windows.usesApkInstallMethod, isFalse);
      expect(PlatformType.linux.usesApkInstallMethod, isFalse);
    });
  });
}
