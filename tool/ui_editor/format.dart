/// 对单个生成文件尽力执行 `dart format`（失败忽略）。
///
/// 只对**明确的一个文件**调用，因此不可能波及其它文件。生成器本身已按
/// `dart format` 风格输出，这一步只是兜底；SDK 不可用（如 AOT 快照）时静默跳过。
///
/// 刻意**不使用 `dart fix`**：它会按本机 SDK 的 lint 集改写代码，与 CI 固定的
/// `stable` 通道漂移，且可能动到非目标文件。
library;

import 'dart:io';

/// 用当前 Dart SDK 格式化 [file]；成功返回 `true`。
Future<bool> tryFormatFile(File file) async {
  try {
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>['format', file.path],
    );
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}
