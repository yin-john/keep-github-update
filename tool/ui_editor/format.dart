/// 对单个生成文件尽力执行 `dart format`（失败忽略）。
///
/// 只对**明确的一个文件**调用，因此不可能波及其它文件。生成器本身已按
/// `dart format` 风格输出，这一步只是兜底；SDK 不可用（如 AOT 快照）时静默跳过。
///
/// 刻意**不使用 `dart fix`**：它会按本机 SDK 的 lint 集改写代码，与 CI 固定的
/// `stable` 通道漂移，且可能动到非目标文件。
library;

import 'dart:io';

/// [script] 是否表示「以源码形式跑在 Dart VM 下」。
///
/// 这是判断能否安全调用 `dart format` 的依据：`dart compile exe` 产出的可执行
/// 文件里 `Platform.resolvedExecutable` 指向**本程序自己**，照着再跑一次会启动
/// 第二个编辑器服务且永不退出，保存请求就会挂死。kernel 快照（`.dill`）同理。
bool isSourceScriptUri(Uri script) =>
    script.scheme == 'file' && script.path.endsWith('.dart');

/// 当前进程能否安全执行 `dart format`。
bool canRunDartFormat() {
  try {
    return isSourceScriptUri(Platform.script);
  } on Object {
    // 某些运行形态下 Platform.script 会抛错，按不可用处理。
    return false;
  }
}

/// 用当前 Dart SDK 格式化 [file]；成功返回 `true`。
///
/// 只有在源码形态下才真正执行，否则直接返回 `false`（见 [canRunDartFormat]）。
Future<bool> tryFormatFile(File file) async {
  if (!canRunDartFormat()) {
    return false;
  }
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
