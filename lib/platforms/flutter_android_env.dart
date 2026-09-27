/// GUI（Flutter）侧的 Android 环境实现：通过 MethodChannel 调用 MainActivity。
/// 非 Android 平台所有调用安全返回 false / null。
library;

import 'package:flutter/services.dart';
import '../core/platform/android_env.dart';
import '../core/platform/apk_info.dart';

class FlutterAndroidEnv extends AndroidEnv {
  const FlutterAndroidEnv();
  static const MethodChannel _channel = MethodChannel('grku/native');

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> hasStoragePermission() async =>
      await _invoke<bool>('hasStoragePermission') ?? false;

  /// 打开「所有文件访问」授权页（Android 11+）或弹出存储权限申请
  @override
  Future<bool> requestStoragePermission() async =>
      await _invoke<bool>('requestStoragePermission') ?? false;

  @override
  Future<bool> hasNotificationPermission() async =>
      await _invoke<bool>('hasNotificationPermission') ?? false;

  @override
  Future<bool> requestNotificationPermission() async =>
      await _invoke<bool>('requestNotificationPermission') ?? false;

  @override
  Future<bool> hasRoot() async => await _invoke<bool>('hasRoot') ?? false;

  @override
  Future<bool> requestRoot() async => await _invoke<bool>('requestRoot') ?? false;

  @override
  Future<bool> hasShizuku() async => await _invoke<bool>('hasShizuku') ?? false;

  @override
  Future<bool> requestShizuku() async =>
      await _invoke<bool>('requestShizuku') ?? false;

  @override
  Future<String?> apkSignature(String path) async =>
      await _invoke<String>('apkSignature', {'path': path});

  @override
  Future<String?> apkPackageName(String path) async =>
      await _invoke<String>('apkPackageName', {'path': path});

  @override
  Future<String?> installedSignature(String packageName) async =>
      await _invoke<String>('installedSignature', {'package': packageName});

  @override
  Future<String?> installedAppVersion(String packageName) async =>
      await _invoke<String>('installedVersion', {'package': packageName});

  @override
  Future<String?> selfPackageName() async =>
      await _invoke<String>('selfPackageName');

  @override
  Future<ApkAppInfo> apkAppInfo(String path) async =>
      ApkAppInfo.fromChannel(await _invoke<Object>('apkAppInfo', {'path': path}));

  @override
  Future<ApkAppInfo> installedAppInfo(String packageName) async =>
      ApkAppInfo.fromChannel(await _invoke<Object>(
          'installedAppInfo', {'package': packageName}));

  @override
  Future<bool> startBackgroundService({String? title, String? text}) async =>
      await _invoke<bool>('startBackgroundService', {
        if (title != null) 'title': title,
        if (text != null) 'text': text,
      }) ??
      false;

  @override
  Future<bool> updateBackgroundNotification(String title, String text) async =>
      await _invoke<bool>('updateBackgroundNotification',
          {'title': title, 'text': text}) ??
      false;

  @override
  Future<bool> stopBackgroundService() async =>
      await _invoke<bool>('stopBackgroundService') ?? false;

  @override
  Future<bool> isBackgroundServiceRunning() async =>
      await _invoke<bool>('isBackgroundServiceRunning') ?? false;

  @override
  Future<bool> installWithSystem(String path) async =>
      await _invoke<bool>('installWithSystem', {'path': path}) ?? false;

  @override
  Future<String?> appFilesDir() async => await _invoke<String>('filesDir');

  @override
  Future<String?> appExternalFilesDir() async =>
      await _invoke<String>('externalFilesDir');
}
