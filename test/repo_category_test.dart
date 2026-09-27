/// 仓库分类：普通应用 / Xposed(LSPosed) 模块 / Magisk-KernelSU 模块。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';

const _apkRule = AssetRule(
  platform: PlatformType.android,
  strategy: UpdateStrategy.apk,
  nameRegex: r'.*\.apk$',
);

const _moduleRule = AssetRule(
  platform: PlatformType.android,
  strategy: UpdateStrategy.module,
  nameRegex: r'.*\.zip$',
);

const _portableRule = AssetRule(
  platform: PlatformType.windows,
  strategy: UpdateStrategy.portable,
  nameRegex: r'.*\.zip$',
);

RepoConfig _repo(List<AssetRule> rules, {bool xposed = false}) => RepoConfig(
      id: 'o/r',
      owner: 'o',
      repo: 'r',
      assetRules: rules,
      xposedModule: xposed,
    );

void main() {
  group('RepoConfig 分类判定', () {
    test('APK 策略且未声明 xposedmodule → 普通应用', () {
      final r = _repo([_apkRule]);
      expect(r.isApkRepo, isTrue);
      expect(r.isXposedModuleRepo, isFalse);
      expect(r.isMagiskModuleRepo, isFalse);
      expect(r.isNormalAppRepo, isTrue);
    });

    test('APK 策略且声明 xposedmodule → LSPosed 模块', () {
      final r = _repo([_apkRule], xposed: true);
      expect(r.isXposedModuleRepo, isTrue);
      expect(r.isNormalAppRepo, isFalse);
      expect(r.isMagiskModuleRepo, isFalse);
    });

    test('module 策略 → Magisk/KernelSU 模块', () {
      final r = _repo([_moduleRule]);
      expect(r.isMagiskModuleRepo, isTrue);
      expect(r.isNormalAppRepo, isFalse);
      expect(r.isXposedModuleRepo, isFalse);
    });

    test('桌面 portable 策略 → 普通应用', () {
      final r = _repo([_portableRule]);
      expect(r.isNormalAppRepo, isTrue);
      expect(r.isXposedModuleRepo, isFalse);
      expect(r.isMagiskModuleRepo, isFalse);
    });

    test('xposedModule 默认 false（旧配置兼容）', () {
      final r = _repo([_apkRule]);
      expect(r.xposedModule, isFalse);
    });

    test('xposedModule 持久化往返', () {
      final r = _repo([_apkRule], xposed: true);
      final j = r.toJson();
      expect(j['xposedModule'], true);
      expect(RepoConfig.fromJson(j).xposedModule, isTrue);
      // false 时不写入字段
      expect(_repo([_apkRule]).toJson().containsKey('xposedModule'), isFalse);
    });

    test('copyWith 可更新 xposedModule', () {
      final r = _repo([_apkRule]).copyWith(xposedModule: true);
      expect(r.xposedModule, isTrue);
    });
  });
}
