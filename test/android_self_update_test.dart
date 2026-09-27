/// 回归测试：Android 端「自己更新自己」时，
/// 即使签名不一致且开启了「无视签名强制安装」，也绝不能卸载自身。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/app_paths.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/core/github/release_model.dart';
import 'package:github_releases_keep_update/core/platform/android_env.dart';
import 'package:github_releases_keep_update/core/platform/bridge.dart';
import 'package:github_releases_keep_update/platforms/android_updater.dart';

/// 只实现测试用得到的方法，其余交给 noSuchMethod
class _FakeEnv implements AndroidEnv {
  _FakeEnv({
    required this.selfPkg,
    required this.apkPkg,
    required this.installedSig,
    required this.apkSig,
  });

  final String selfPkg;
  final String apkPkg;
  final String installedSig;
  final String apkSig;

  @override
  bool get isAndroid => true;

  @override
  Future<String?> selfPackageName() async => selfPkg;

  @override
  Future<String?> apkPackageName(String path) async => apkPkg;

  @override
  Future<String?> installedSignature(String packageName) async => installedSig;

  @override
  Future<String?> apkSignature(String path) async => apkSig;

  @override
  Future<bool> installWithSystem(String path) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBridge implements PlatformBridge {
  final uninstalled = <String>[];
  final installed = <String>[];

  @override
  Future<void> uninstallApk(String packageName, {bool keepData = true}) async {
    uninstalled.add(packageName);
  }

  @override
  Future<void> installApk(String path, {required InstallMethod method}) async {
    installed.add(path);
  }

  @override
  Future<void> flashModule(String path) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _apkRule = AssetRule(
  platform: PlatformType.android,
  strategy: UpdateStrategy.apk,
  nameRegex: r'.*\.apk$',
);

RepoConfig _repo() => const RepoConfig(
      id: 'o/r',
      owner: 'o',
      repo: 'r',
      assetRules: [_apkRule],
    );

const _asset = Asset(name: 'app.apk', browserDownloadUrl: 'http://x/a.apk', size: 1);

void main() {
  test('自更新 + 签名不一致：拒绝安装，且绝不卸载自身', () async {
    // 仓库指向本应用自己的 release，未配置 packageName（包名由 APK 推断）
    final env = _FakeEnv(
      selfPkg: androidPackageId,
      apkPkg: androidPackageId,
      installedSig: 'aa11',
      apkSig: 'bb22',
    );
    final bridge = _FakeBridge();
    // ignoreSignature = true：这是触发「先卸载再安装」的危险开关
    final updater = AndroidUpdater(bridge, InstallMethod.root, env, true);

    await expectLater(
      updater.apply(
        asset: _asset,
        localPath: '/tmp/app.apk',
        repo: _repo(),
        rule: _apkRule,
      ),
      throwsA(isA<Exception>()),
    );

    expect(bridge.uninstalled, isEmpty, reason: '不允许把自己卸载掉');
    expect(bridge.installed, isEmpty, reason: '签名冲突时不应继续安装');
  });

  test('自更新 + 签名一致：正常覆盖安装，不卸载', () async {
    final env = _FakeEnv(
      selfPkg: androidPackageId,
      apkPkg: androidPackageId,
      installedSig: 'aa11',
      apkSig: 'aa11',
    );
    final bridge = _FakeBridge();
    final updater = AndroidUpdater(bridge, InstallMethod.root, env, true);

    await updater.apply(
      asset: _asset,
      localPath: '/tmp/app.apk',
      repo: _repo(),
      rule: _apkRule,
    );

    expect(bridge.uninstalled, isEmpty);
    expect(bridge.installed, ['/tmp/app.apk']);
  });

  test('第三方应用 + 签名不一致 + 强制安装：保持原有「先卸载再安装」', () async {
    final env = _FakeEnv(
      selfPkg: androidPackageId,
      apkPkg: 'com.other.app',
      installedSig: 'aa11',
      apkSig: 'bb22',
    );
    final bridge = _FakeBridge();
    final updater = AndroidUpdater(bridge, InstallMethod.root, env, true);

    await updater.apply(
      asset: _asset,
      localPath: '/tmp/other.apk',
      repo: _repo(),
      rule: _apkRule,
    );

    expect(bridge.uninstalled, ['com.other.app']);
    expect(bridge.installed, ['/tmp/other.apk']);
  });

  test('第三方应用 + 签名不一致 + 未开启强制安装：拒绝且不卸载', () async {
    final env = _FakeEnv(
      selfPkg: androidPackageId,
      apkPkg: 'com.other.app',
      installedSig: 'aa11',
      apkSig: 'bb22',
    );
    final bridge = _FakeBridge();
    final updater = AndroidUpdater(bridge, InstallMethod.root, env, false);

    await expectLater(
      updater.apply(
        asset: _asset,
        localPath: '/tmp/other.apk',
        repo: _repo(),
        rule: _apkRule,
      ),
      throwsA(isA<Exception>()),
    );
    expect(bridge.uninstalled, isEmpty);
    expect(bridge.installed, isEmpty);
  });
}
