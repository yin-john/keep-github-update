/// 本地 APK 信息提取测试：优先用已下载的 APK，图标/名称/包名/版本落盘到下载目录。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/platform/android_env.dart';
import 'package:github_releases_keep_update/core/platform/apk_info.dart';
import 'package:github_releases_keep_update/core/platform/apk_local_info.dart';
import 'package:path/path.dart' as p;

import 'support/fs.dart';

class _FakeEnv implements AndroidEnv {
  _FakeEnv(this.info);
  ApkAppInfo info;
  int calls = 0;

  @override
  Future<ApkAppInfo> apkAppInfo(String path) async {
    calls++;
    return info;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('grku_apkinfo_'));
  tearDown(() => deleteDirQuietly(tmp));

  File apkIn(String dir, String name) =>
      File(p.join(dir, name))..writeAsBytesSync([9, 9, 9]);

  test('显式 apkPath：图标复制为 app_icon.png，名称/包名/版本写入 app_name.txt', () async {
    final dir = p.join(tmp.path, 'dl');
    Directory(dir).createSync(recursive: true);
    final srcIcon = File(p.join(tmp.path, 'src.png'))
      ..writeAsBytesSync([1, 2, 3, 4]);
    final env = _FakeEnv(const ApkAppInfo(
      label: '示例应用',
      packageName: 'com.example.app',
      version: '1.2.3',
      iconPath: srcIcon.path,
    ));
    final apk = apkIn(dir, 'app-1.2.3.apk');

    final info = await extractApkInfoIntoDir(env, dir, apkPath: apk.path);

    expect(info?.label, '示例应用');
    expect(info?.packageName, 'com.example.app');
    expect(info?.version, '1.2.3');
    expect(info?.iconPath, p.join(dir, apkIconFileName));
    expect(File(p.join(dir, apkIconFileName)).readAsBytesSync(), [1, 2, 3, 4]);
    final txt = File(p.join(dir, apkNameFileName)).readAsStringSync();
    expect(txt, contains('名称: 示例应用'));
    expect(txt, contains('包名: com.example.app'));
    expect(txt, contains('版本: 1.2.3'));
    expect(env.calls, 1);
  });

  test('目录不存在 / 没有 APK：返回 null 且不调用原生', () async {
    final env = _FakeEnv(const ApkAppInfo(label: 'x'));
    expect(await extractApkInfoIntoDir(env, p.join(tmp.path, 'nope')), isNull);

    final dir = p.join(tmp.path, 'empty');
    Directory(dir).createSync(recursive: true);
    File(p.join(dir, 'checksum.txt')).writeAsStringSync('abc');
    expect(await extractApkInfoIntoDir(env, dir), isNull);
    expect(env.calls, 0);
  });

  test('多个 APK 时取修改时间最新的一个', () async {
    final dir = p.join(tmp.path, 'dl');
    Directory(dir).createSync(recursive: true);
    apkIn(dir, 'app-1.0.0.apk')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    apkIn(dir, 'app-2.0.0.apk')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));
    final env = _FakeEnv(const ApkAppInfo(label: '新版本应用'));

    final info = await extractApkInfoIntoDir(env, dir);

    expect(info?.label, '新版本应用');
    expect(env.calls, 1);
    expect(File(p.join(dir, apkNameFileName)).readAsStringSync(),
        contains('新版本应用'));
  });

  test('已有产物且比 APK 新：命中缓存，从 txt 解析，不再调用原生', () async {
    final dir = p.join(tmp.path, 'dl');
    Directory(dir).createSync(recursive: true);
    final apk = apkIn(dir, 'app.apk')
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    final srcIcon = File(p.join(tmp.path, 'src.png'))
      ..writeAsBytesSync([7, 7]);
    final env = _FakeEnv(const ApkAppInfo(
      label: '示例应用',
      packageName: 'com.example.app',
      version: '1.2.3',
      iconPath: srcIcon.path,
    ));

    await extractApkInfoIntoDir(env, dir, apkPath: apk.path);
    expect(env.calls, 1);

    final info = await extractApkInfoIntoDir(env, dir);
    expect(info?.label, '示例应用');
    expect(info?.packageName, 'com.example.app');
    expect(info?.version, '1.2.3');
    expect(env.calls, 1, reason: '缓存命中时不应再次提取');
  });

  test('APK 比缓存新（刚更新过）→ 重新提取', () async {
    final dir = p.join(tmp.path, 'dl');
    Directory(dir).createSync(recursive: true);
    final srcIcon = File(p.join(tmp.path, 'src.png'))
      ..writeAsBytesSync([7, 7]);
    final env = _FakeEnv(const ApkAppInfo(label: '示例应用', iconPath: srcIcon.path));

    final apk = apkIn(dir, 'app-1.0.0.apk');
    await extractApkInfoIntoDir(env, dir, apkPath: apk.path);
    expect(env.calls, 1);

    apk.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    final info = await extractApkInfoIntoDir(env, dir);
    expect(info?.label, '示例应用');
    expect(env.calls, 2, reason: 'APK 更新后应重新提取');
  });

  test('兼容旧格式 txt（首行即名称），命中缓存不调用原生', () async {
    final dir = p.join(tmp.path, 'dl');
    Directory(dir).createSync(recursive: true);
    apkIn(dir, 'app.apk')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    File(p.join(dir, apkIconFileName)).writeAsBytesSync([1]);
    File(p.join(dir, apkNameFileName)).writeAsStringSync('旧格式名称\n');
    final env = _FakeEnv(const ApkAppInfo());

    final info = await extractApkInfoIntoDir(env, dir);

    expect(info?.label, '旧格式名称');
    expect(info?.iconPath, p.join(dir, apkIconFileName));
    expect(env.calls, 0, reason: '命中缓存不应调用原生');
  });

  test('原生提取失败 / 返回空信息：返回 null 且不崩溃', () async {
    final dir = p.join(tmp.path, 'dl');
    Directory(dir).createSync(recursive: true);
    apkIn(dir, 'app.apk');
    final env = _FakeEnv(const ApkAppInfo());

    final info = await extractApkInfoIntoDir(env, dir);
    expect(info, isNull);
    expect(File(p.join(dir, apkNameFileName)).existsSync(), isFalse);
  });
}
