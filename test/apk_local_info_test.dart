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
  ApkAppInfo installedInfo = const ApkAppInfo();
  int installedCalls = 0;

  @override
  Future<ApkAppInfo> apkAppInfo(String path) async {
    calls++;
    return info;
  }

  @override
  Future<ApkAppInfo> installedAppInfo(String packageName) async {
    installedCalls++;
    return installedInfo;
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
    final env = _FakeEnv(ApkAppInfo(
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
    final env = _FakeEnv(ApkAppInfo(
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
    final env = _FakeEnv(ApkAppInfo(label: '示例应用', iconPath: srcIcon.path));

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

  test('结构化缓存缺「Xposed 模块:」行（旧版产生）→ 视为过期重新提取', () async {
    final dir = p.join(tmp.path, 'dl');
    Directory(dir).createSync(recursive: true);
    apkIn(dir, 'app.apk')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    final srcIcon = File(p.join(tmp.path, 'src.png'))
      ..writeAsBytesSync([8, 8]);
    File(p.join(dir, apkIconFileName)).writeAsBytesSync([1]);
    // 旧版结构化格式：有「名称:」但无 Xposed 行
    File(p.join(dir, apkNameFileName))
        .writeAsStringSync('名称: 旧缓存应用\n包名: com.old\n版本: 1.0\n');
    final env = _FakeEnv(ApkAppInfo(
      label: '重提取应用',
      packageName: 'com.new',
      iconPath: srcIcon.path,
      xposed: true,
    ));

    final info = await extractApkInfoIntoDir(env, dir);

    expect(env.calls, 1, reason: '缺 Xposed 标记的旧缓存应重新提取');
    expect(info?.label, '重提取应用');
    expect(info?.xposed, isTrue);
    // 重提取后的缓存包含提取器 v2 标记，再次调用命中缓存
    final again = await extractApkInfoIntoDir(env, dir);
    expect(again?.xposed, isTrue);
    expect(env.calls, 1, reason: '新缓存应直接命中');
    expect(File(p.join(dir, apkNameFileName)).readAsStringSync(),
        contains('Xposed 模块: 是'));
  });

  test('旧提取器（0.2.13）生成的缓存 → 视为过期重新提取', () async {
    final dir = p.join(tmp.path, 'dl');
    Directory(dir).createSync(recursive: true);
    apkIn(dir, 'app.apk')
        .setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    final srcIcon = File(p.join(tmp.path, 'src.png'))
      ..writeAsBytesSync([5, 5]);
    File(p.join(dir, apkIconFileName)).writeAsBytesSync([1]);
    // 0.2.13 格式：有 Xposed 行但无「提取器: v2」标记（当时还识别不出新式模块）
    File(p.join(dir, apkNameFileName)).writeAsStringSync(
        '名称: 旧检测应用\n包名: com.old\n版本: 1.0\nXposed 模块: 否\n');
    final env = _FakeEnv(const ApkAppInfo(
      label: '新检测应用',
      iconPath: srcIcon.path,
      xposed: true,
    ));

    final info = await extractApkInfoIntoDir(env, dir);

    expect(env.calls, 1, reason: '旧提取器缓存应重新提取');
    expect(info?.xposed, isTrue);
    // 新缓存带 v2 标记，后续命中
    final again = await extractApkInfoIntoDir(env, dir);
    expect(again?.xposed, isTrue);
    expect(env.calls, 1);
  });

  test('Xposed 应用：提取结果带 xposed 标记并写入缓存', () async {
    final dir = p.join(tmp.path, 'dl');
    Directory(dir).createSync(recursive: true);
    final apk = apkIn(dir, 'app.apk')
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    final srcIcon = File(p.join(tmp.path, 'src.png'))
      ..writeAsBytesSync([9, 9]);
    final env = _FakeEnv(ApkAppInfo(
      label: 'XP 模块',
      packageName: 'com.xp.mod',
      iconPath: srcIcon.path,
      xposed: true,
    ));

    final info = await extractApkInfoIntoDir(env, dir, apkPath: apk.path);

    expect(info?.xposed, isTrue);
    final txt = File(p.join(dir, apkNameFileName)).readAsStringSync();
    expect(txt, contains('Xposed 模块: 是'));
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

  test('已安装应用提取：目录自动创建，图标与信息落盘', () async {
    final dir = p.join(tmp.path, 'dl-not-exists');
    final srcIcon = File(p.join(tmp.path, 'installed.png'))
      ..writeAsBytesSync([4, 5, 6]);
    final env = _FakeEnv(const ApkAppInfo())
      ..installedInfo = ApkAppInfo(
        label: '已装应用',
        packageName: 'com.example.installed',
        version: '2.0.0',
        iconPath: srcIcon.path,
      );

    final info = await extractInstalledAppInfoIntoDir(
        env, dir, 'com.example.installed');

    expect(info?.label, '已装应用');
    expect(info?.packageName, 'com.example.installed');
    expect(info?.version, '2.0.0');
    expect(info?.iconPath, p.join(dir, apkIconFileName));
    expect(Directory(dir).existsSync(), isTrue, reason: '目录不存在时应自动创建');
    expect(File(p.join(dir, apkIconFileName)).readAsBytesSync(), [4, 5, 6]);
    final txt = File(p.join(dir, apkNameFileName)).readAsStringSync();
    expect(txt, contains('名称: 已装应用'));
    expect(txt, contains('版本: 2.0.0'));
    expect(env.installedCalls, 1);
  });

  test('已安装应用提取：包名为空 / 应用信息为空 → 返回 null', () async {
    final dir = p.join(tmp.path, 'dl2');
    final env = _FakeEnv(const ApkAppInfo());

    expect(await extractInstalledAppInfoIntoDir(env, dir, ''), isNull);
    expect(await extractInstalledAppInfoIntoDir(env, dir, '  '), isNull);

    final info =
        await extractInstalledAppInfoIntoDir(env, dir, 'com.missing.app');
    expect(info, isNull, reason: '应用未安装（空信息）时应返回 null');
    expect(Directory(dir).existsSync(), isFalse, reason: '无信息时不应创建目录');
  });
}
