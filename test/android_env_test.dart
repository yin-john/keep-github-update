import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/app_paths.dart';
import 'package:github_releases_keep_update/core/platform/android_env.dart';

void main() {
  group('AndroidEnv 在非 Android 平台安全降级', () {
    const env = ShellAndroidEnv();

    test('权限与 root 检测返回 false 而不是抛异常', () async {
      expect(await env.hasStoragePermission(), isFalse);
      expect(await env.hasNotificationPermission(), isFalse);
      expect(await env.hasRoot(), isFalse);
      expect(await env.hasShizuku(), isFalse);
      expect(await env.requestStoragePermission(), isFalse);
      expect(await env.requestRoot(), isFalse);
    });

    test('签名 / 包信息读取返回 null', () async {
      expect(await env.apkSignature(r'C:\tmp\a.apk'), isNull);
      expect(await env.apkPackageName(r'C:\tmp\a.apk'), isNull);
      expect(await env.installedSignature('com.foo'), isNull);
      expect(await env.appFilesDir(), isNull);
      expect(await env.appExternalFilesDir(), isNull);
    });
  });

  group('Android 路径推导', () {
    tearDown(resetAppBaseDir);

    test('公共存储根目录有确定性回退', () {
      expect(androidExternalRoot(), isNotEmpty);
      expect(androidExternalRoot().startsWith('/'), isTrue);
    });

    test('可覆盖为应用私有目录（启动时由系统 API 设置）', () {
      setAppBaseDir('/data/user/0/com.example/files');
      expect(androidPrivateRoot(), '/data/user/0/com.example/files');
      resetAppBaseDir();
      expect(androidPrivateRoot(), contains(androidPackageId));
    });

    test('默认下载目录 / 回退目录均可用', () {
      expect(defaultDownloadDir(), isNotEmpty);
      expect(fallbackDownloadDir(), isNotEmpty);
      // 下载目录与仓库子目录拼接关系
      expect(repoDownloadDir('o', 'r', baseDir: '/tmp/base'),
          equals('${'/tmp/base'}${Platform.pathSeparator}o@r'));
    });
  });
}
