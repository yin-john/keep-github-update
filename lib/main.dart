import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/config/app_paths.dart';
import 'core/log/app_log.dart';
import 'core/platform/bridge.dart';
import 'platforms/flutter_android_env.dart';
import 'platforms/flutter_system_notifier.dart';
import 'ui/providers/app_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android：先解析出真正可写的应用内部目录，再加载/保存配置
  if (Platform.isAndroid) {
    try {
      final dir = await const FlutterAndroidEnv().appFilesDir();
      if (dir != null && dir.isNotEmpty) setAppBaseDir(dir);
    } catch (_) {
      // 解析失败时退回默认推导路径
    }
    // 配置文件与 logs/ 放同一父目录（公共存储 <外部存储>/grku/）；
    // 无「所有文件访问」权限时自动回退应用私有目录
    try {
      setConfigPathOverride(resolveAndroidConfigPath(
        publicRoot: androidPublicRoot(),
        privateConfigPath: fallbackConfigPath(),
      ));
    } catch (_) {
      // 探测失败时保持默认推导路径
    }
    AppLog.refreshPaths(); // 日志路径随之更新（优先公共目录）
  }
  final system = await FlutterSystemNotifier.init();
  final arch = await const DefaultPlatformBridge().deviceArch();
  runApp(ProviderScope(
    overrides: [
      systemNotifierProvider.overrideWithValue(system),
      deviceArchProvider.overrideWithValue(arch),
    ],
    child: const App(),
  ));
}
