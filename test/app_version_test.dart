import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/version/app_version.dart';
import 'package:github_releases_keep_update/cli/cli_runner.dart';

void main() {
  test('appVersionDefault 与 pubspec.yaml 的 version 保持一致', () {
    // flutter test 的工作目录是包根目录
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([^\s+]+)', multiLine: true)
        .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml 中未找到 version 字段');
    expect(
      appVersionDefault,
      m!.group(1),
      reason: '改了 pubspec.yaml 的 version，请同步更新 '
          'lib/core/version/app_version.dart 的 appVersionDefault',
    );
  });

  test('versionLine 输出可被脚本解析（grku x.y.z）', () {
    expect(versionLine(), matches(RegExp(r'^grku \d+\.\d+\.\d+')));
    expect(versionLine(), contains(appVersion));
  });

  test('顶层 --version / -V 与 version 子命令都能拿到版本', () async {
    final runner = GrkuCommandRunner('unused.yaml');
    // 不应抛异常，且命令已注册
    expect(runner.commands.containsKey('version'), isTrue);
    await runner.run(['--version']);
    await runner.run(['-V']);
    await runner.run(['version']);
  });
}
