/// CLI / TUI 入口（纯 Dart，可在 Windows/Linux 下 `dart run bin/grku.dart` 运行）
library;

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:github_releases_keep_update/cli/cli_runner.dart';
import 'package:github_releases_keep_update/cli/app_context.dart';

void main(List<String> args) async {
  final runner = GrkuCommandRunner(defaultConfigPath());
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    print(e.message);
    print(e.usage);
    exit(1);
  } catch (e) {
    print('错误: $e');
    exit(1);
  }
}
