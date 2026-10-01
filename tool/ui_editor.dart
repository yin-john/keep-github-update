/// 可视化 Flutter UI 编辑器（开发期工具）。
///
/// 用法（在项目根目录执行）：
/// ```
/// dart run tool/ui_editor.dart [--port 8765] [--no-open] [--no-format]
/// dart run tool/ui_editor.dart --host 0.0.0.0     # 让局域网也能访问
/// ```
///
/// 启动一个**仅监听 127.0.0.1** 的 HTTP 服务，浏览器打开后即可拖拽生成 Flutter
/// 界面。保存会写入 `lib/ui/generated/<Name>.dart`，对正在运行的 `flutter run`
/// 热重载即可看到效果。
///
/// 注意：这是**开发期**工具——生成的代码需要重新编译（或热重载）才能生效，
/// 安装版（exe / apk）没有 `lib/` 源码，无法使用。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';

import 'ui_editor/project.dart';
import 'ui_editor/server.dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('port',
        abbr: 'p', defaultsTo: '0', help: '监听端口；0 表示自动分配')
    ..addOption('host',
        defaultsTo: '127.0.0.1',
        help: '监听地址；用 0.0.0.0 让局域网也能访问（会削弱隔离性）')
    ..addFlag('open', defaultsTo: true, help: '启动后自动打开浏览器')
    ..addFlag('format', defaultsTo: true, help: '保存后尽力执行 dart format');
  final args = parser.parse(argv);

  final root = findProjectRoot(Directory.current);
  final assets = resolveWebAssetsDir();
  final token = _randomToken();
  final port = int.tryParse(args.option('port') ?? '0') ?? 0;

  final server = await EditorServer.start(
    rootDir: root,
    assetsDir: assets,
    token: token,
    port: port,
    host: args.option('host') ?? '127.0.0.1',
    formatOnSave: args.flag('format'),
  );

  final localUrl = 'http://127.0.0.1:${server.port}/?token=$token';
  stdout
    ..writeln('项目根目录：${root.path}')
    ..writeln('生成目录：  ${generatedDir(root).path}')
    ..writeln();

  if (server.isLoopbackOnly) {
    stdout
      ..writeln('UI 编辑器已启动：$localUrl')
      ..writeln('（地址含本次会话的随机令牌，请勿分享；服务仅监听 127.0.0.1）');
  } else {
    stdout
      ..writeln('UI 编辑器已启动（已监听 ${server.bindAddress.address}，局域网可访问）：')
      ..writeln('  本机：   $localUrl');
    for (final ip in await _lanIPv4Addresses()) {
      stdout.writeln('  局域网： http://$ip:${server.port}/?token=$token');
    }
    stdout.writeln('⚠️  同网段任何人都能打开这个页面；令牌等同于密码，不要外传。');
  }
  stdout.writeln('按 Ctrl+C 退出。');

  if (args.flag('open')) {
    await _openBrowser(localUrl);
  }

  final subscription = ProcessSignal.sigint.watch().listen((ProcessSignal _) {
    unawaited(server.close());
  });
  await server.done;
  await subscription.cancel();
  stdout.writeln('已退出。');
}

/// 每次运行生成一个随机访问令牌（32 字节，base64url 无填充）。
String _randomToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// 枚举本机非回环的 IPv4 地址，用于打印局域网访问地址。
///
/// 枚举失败时返回空列表——拿不到 IP 不该让服务起不来。
Future<List<String>> _lanIPv4Addresses() async {
  final result = <String>[];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        result.add(address.address);
      }
    }
  } on Object {
    // 忽略：用户可自行用 ip addr / ipconfig 查地址。
  }
  return result;
}

/// 尽力用系统浏览器打开 [url]；失败不影响服务。
Future<void> _openBrowser(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.run('cmd', <String>['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      await Process.run('open', <String>[url]);
    } else {
      await Process.run('xdg-open', <String>[url]);
    }
  } on Object {
    // 打不开浏览器时，用户可手动复制上面的地址。
  }
}
