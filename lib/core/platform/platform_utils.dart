/// 运行时平台识别
library;

import 'dart:io';
import '../config/models.dart';

PlatformType currentPlatformType() {
  if (Platform.isAndroid) return PlatformType.android;
  if (Platform.isWindows) return PlatformType.windows;
  if (Platform.isLinux) return PlatformType.linux;
  // iOS/macOS 等暂不支持
  throw UnsupportedError('当前平台不支持: ${Platform.operatingSystem}');
}
