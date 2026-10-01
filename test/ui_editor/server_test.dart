import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/ui_editor/server.dart';
import '../support/fs.dart';

void main() {
  const token = 'test-token';
  late Directory root;
  late Directory assets;
  late EditorServer server;
  late HttpClient client;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('grku_ui_root');
    assets = await Directory.systemTemp.createTemp('grku_ui_assets');
    await File(p.join(assets.path, 'index.html')).writeAsString('<html>ok</html>');
    server = await EditorServer.start(
      rootDir: root,
      assetsDir: assets,
      token: token,
      formatOnSave: false,
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    await deleteDirQuietly(root);
    await deleteDirQuietly(assets);
  });

  Future<({int status, String body, HttpHeaders headers})> call(
    String method,
    String path, {
    Object? body,
    String? tokenHeader,
    String? contentType,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (tokenHeader != null) {
      request.headers.set('x-editor-token', tokenHeader);
    }
    if (body != null || contentType != null) {
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        contentType ?? 'application/json',
      );
    }
    if (body != null) {
      request.write(body is String ? body : jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: text, headers: response.headers);
  }

  /// 直接发原始请求：可以完全控制 Host 头（HttpClient 未必允许覆盖）。
  Future<String> rawRequest(String request, {int? port}) async {
    final socket = await Socket.connect('127.0.0.1', port ?? server.port);
    socket.write(request);
    await socket.flush();

    final buffer = StringBuffer();
    final done = Completer<void>();
    final subscription = socket.listen(
      (List<int> data) {
        // 分块可能切断多字节字符，容错解码。
        buffer.write(utf8.decode(data, allowMalformed: true));
        if (!done.isCompleted) {
          done.complete();
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete();
        }
      },
    );
    // 只等第一段响应，避免服务端保持连接时挂住。
    try {
      await done.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // 超时就直接用已收到的内容断言。
    }
    await subscription.cancel();
    socket.destroy();
    return buffer.toString();
  }

  Map<String, Object?> tree([String type = 'Text']) => <String, Object?>{
        'type': type,
        'props': <String, Object?>{},
        'children': <Object?>[],
      };

  test('GET /api/palette 需要正确 token', () async {
    expect((await call('GET', '/api/palette')).status, 401);
    expect(
      (await call('GET', '/api/palette', tokenHeader: 'wrong')).status,
      401,
    );
    final ok = await call('GET', '/api/palette', tokenHeader: token);
    expect(ok.status, 200);
    final decoded = jsonDecode(ok.body);
    expect(decoded, isA<List<Object?>>());
    expect(decoded as List<Object?>, isNotEmpty);
  });

  test('Host 头校验（防 DNS rebinding）', () async {
    final response = await rawRequest(
      'GET /api/palette HTTP/1.1\r\n'
      'Host: evil.example\r\n'
      'X-Editor-Token: $token\r\n'
      'Connection: close\r\n'
      '\r\n',
    );
    expect(response, contains('403'));
  });

  test('监听 0.0.0.0 时接受局域网 IP，仍拒绝域名', () async {
    final lanRoot = await Directory.systemTemp.createTemp('grku_lan_root');
    final lanServer = await EditorServer.start(
      rootDir: lanRoot,
      assetsDir: assets,
      token: token,
      host: '0.0.0.0',
      formatOnSave: false,
    );
    addTearDown(() async {
      await lanServer.close();
      await deleteDirQuietly(lanRoot);
    });

    final port = lanServer.port;
    expect(lanServer.isLoopbackOnly, isFalse);
    expect(
      await rawRequest(
        'GET /api/palette HTTP/1.1\r\n'
        'Host: 192.168.1.50:$port\r\n'
        'X-Editor-Token: $token\r\n'
        'Connection: close\r\n\r\n',
        port: port,
      ),
      contains('200'),
    );
    expect(
      await rawRequest(
        'GET /api/palette HTTP/1.1\r\n'
        'Host: evil.example:$port\r\n'
        'X-Editor-Token: $token\r\n'
        'Connection: close\r\n\r\n',
        port: port,
      ),
      contains('403'),
    );
  });

  test('拒绝 OPTIONS 且不返回 CORS 头', () async {
    final res = await call('OPTIONS', '/api/save', tokenHeader: token);
    expect(res.status, 405);
    expect(res.headers.value('access-control-allow-origin'), isNull);
  });

  test('静态资源无需 token', () async {
    final res = await call('GET', '/');
    expect(res.status, 200);
    expect(res.body, contains('<html>'));
  });

  test('POST /api/save 写盘并产出 sidecar', () async {
    final res = await call('POST', '/api/save', tokenHeader: token, body: {
      'name': 'Demo',
      'tree': tree(),
    });
    expect(res.status, 200);

    final generated = p.join(root.path, 'lib', 'ui', 'generated');
    final dartFile = File(p.join(generated, 'Demo.dart'));
    final designFile = File(p.join(generated, 'Demo.design.json'));
    expect(dartFile.existsSync(), isTrue);
    expect(designFile.existsSync(), isTrue);
    expect(
      dartFile.readAsStringSync(),
      contains('class Demo extends StatelessWidget'),
    );
  });

  test('POST /api/save 拒绝越界类名且不写任何文件', () async {
    final res = await call('POST', '/api/save', tokenHeader: token, body: {
      'name': '../../evil',
      'tree': tree(),
    });
    expect(res.status, 400);
    expect(Directory(p.join(root.path, 'lib')).existsSync(), isFalse);
  });

  test('POST /api/save 覆盖需显式确认', () async {
    final payload = <String, Object?>{'name': 'Demo', 'tree': tree()};
    expect(
      (await call('POST', '/api/save', tokenHeader: token, body: payload)).status,
      200,
    );
    expect(
      (await call('POST', '/api/save', tokenHeader: token, body: payload)).status,
      409,
    );
    expect(
      (await call('POST', '/api/save', tokenHeader: token, body: <String, Object?>{
        ...payload,
        'overwrite': true,
      }))
          .status,
      200,
    );
  });

  test('POST /api/preview 返回与保存一致的代码', () async {
    final res = await call('POST', '/api/preview', tokenHeader: token, body: {
      'tree': <String, Object?>{
        'type': 'Text',
        'props': <String, Object?>{'data': 'Hi'},
        'children': <Object?>[],
      },
    });
    expect(res.status, 200);
    final decoded = jsonDecode(res.body) as Map<String, Object?>;
    expect(decoded['code'], contains(r"const Text('Hi')"));
  });

  test('Content-Type 非 application/json 时返回 415', () async {
    final res = await call(
      'POST',
      '/api/save',
      tokenHeader: token,
      body: 'x',
      contentType: 'text/plain',
    );
    expect(res.status, 415);
  });

  test('方法不匹配时返回 405', () async {
    expect((await call('GET', '/api/save', tokenHeader: token)).status, 405);
  });

  test('设计稿可读写删', () async {
    await call('POST', '/api/save', tokenHeader: token, body: {
      'name': 'Demo',
      'tree': tree(),
    });
    final list = await call('GET', '/api/designs', tokenHeader: token);
    expect(list.status, 200);
    expect(jsonDecode(list.body), contains('Demo'));

    final one = await call('GET', '/api/design?name=Demo', tokenHeader: token);
    expect(one.status, 200);

    final removed = await call('DELETE', '/api/design?name=Demo', tokenHeader: token);
    expect(removed.status, 200);
    expect(
      (await call('GET', '/api/design?name=Demo', tokenHeader: token)).status,
      404,
    );
  });
}
