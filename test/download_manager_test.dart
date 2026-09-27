import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/download/download_manager.dart';

import 'support/fs.dart';
import 'support/test_server.dart';

void main() {
  final data = List<int>.generate(512 * 1024, (i) => i % 251);
  final sha = sha256.convert(data).toString();

  late Directory dir;
  final managers = <DownloadManager>[];

  DownloadManager newManager({int threads = 1}) {
    final m = DownloadManager(threads: threads);
    managers.add(m);
    return m;
  }

  // flutter_test 默认拦截真实网络，这里需要访问本地 HTTP 服务器
  setUpAll(() => HttpOverrides.global = null);
  setUp(() => dir = Directory.systemTemp.createTempSync('grku_dl_'));
  tearDown(() async {
    // 释放 HTTP 连接，避免测试套件退出时挂起
    for (final m in managers) {
      m.dio.close(force: true);
    }
    managers.clear();
    await deleteDirQuietly(dir);
  });

  test('单线程：下载完整并校验通过', () async {
    final server = await TestServer.start(data);
    final manager = newManager();
    var lastTotal = 0;
    final f = await manager.download(
      server.url('/file'),
      '${dir.path}/a.bin',
      expectedChecksum: sha,
      onProgress: (rc, t) => lastTotal = t,
    );
    expect(f.readAsBytesSync(), equals(data));
    expect(lastTotal, data.length);
    await server.close();
  });

  test('多线程分块：下载完整', () async {
    final server = await TestServer.start(data);
    final manager = newManager(threads: 4);
    final f = await manager.download(server.url('/file'), '${dir.path}/a.bin');
    expect(f.readAsBytesSync(), equals(data));
    await server.close();
  });

  test('服务器不支持 Range 时回退单线程仍成功', () async {
    final server = await TestServer.start(data);
    final manager = newManager(threads: 4);
    final f =
        await manager.download(server.url('/norange'), '${dir.path}/a.bin');
    expect(f.readAsBytesSync(), equals(data));
    await server.close();
  });

  test('校验失败：删除文件并抛异常', () async {
    final server = await TestServer.start(data);
    final manager = newManager();
    final path = '${dir.path}/a.bin';
    await expectLater(
      manager.download(server.url('/file'), path, expectedChecksum: 'deadbeef'),
      throwsA(isA<Exception>()),
    );
    expect(File(path).existsSync(), isFalse);
    await server.close();
  });

  test('中断：抛 DownloadCancelled', () async {
    final slow = List<int>.generate(256 * 1024, (i) => i % 251);
    final server = await TestServer.start(slow);
    final manager = newManager();
    final token = CancelToken();
    final fut = manager.download(server.url('/slow'), '${dir.path}/a.bin',
        cancelToken: token);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    token.cancel();
    await expectLater(fut, throwsA(isA<DownloadCancelled>()));
    await server.close();
  });

  test('已存在 .part 分片时续传补齐', () async {
    final server = await TestServer.start(data);
    final manager = newManager();
    final path = '${dir.path}/a.bin';
    // 预置前半段分片，模拟「暂停后继续」
    File('$path.part').writeAsBytesSync(data.sublist(0, data.length ~/ 2));

    final f = await manager.download(server.url('/file'), path);

    expect(f.readAsBytesSync(), equals(data));
    expect(File('$path.part').existsSync(), isFalse);
    await server.close();
  });
}
