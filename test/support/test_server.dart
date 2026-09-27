import 'dart:io';

/// 测试用 HTTP 服务器：提供带 Range 支持的文件下载。
///
/// - `/file`    支持 Range（Accept-Ranges: bytes），用于多线程分块与单线程
/// - `/norange` 不支持 Range（也无法分块），用于验证回退单线程
/// - `/slow`    慢速分块发送，用于验证中断
class TestServer {

  TestServer._(this._server, this.data);
  final HttpServer _server;
  final List<int> data;

  int get port => _server.port;

  String url(String path) => 'http://127.0.0.1:$port$path';

  static Future<TestServer> start(List<int> data) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final t = TestServer._(server, data);
    server.listen(t._handle);
    return t;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final ranges = req.uri.path != '/norange';
      final slow = req.uri.path == '/slow';
      if (ranges) res.headers.set('Accept-Ranges', 'bytes');

      if (req.method == 'HEAD') {
        res.headers.set('Content-Length', '${data.length}');
        await res.close();
        return;
      }

      final range = ranges ? req.headers.value('range') : null;
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
        if (m != null) {
          final start = int.parse(m.group(1)!);
          if (start >= data.length) {
            res.statusCode = 416;
            await res.close();
            return;
          }
          final endRaw = m.group(2)!;
          final end =
              endRaw.isEmpty ? data.length - 1 : int.parse(endRaw);
          final end2 = end < data.length ? end : data.length - 1;
          final slice = data.sublist(start, end2 + 1);
          res.statusCode = 206;
          res.headers
              .set('Content-Range', 'bytes $start-$end2/${data.length}');
          res.headers.set('Content-Length', '${slice.length}');
          res.add(slice);
          await res.close();
          return;
        }
      }

      res.headers.set('Content-Length', '${data.length}');
      if (slow) {
        const step = 4096;
        for (var i = 0; i < data.length; i += step) {
          final e = (i + step) < data.length ? i + step : data.length;
          res.add(data.sublist(i, e));
          await res.flush();
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
      } else {
        res.add(data);
      }
      await res.close();
    } catch (_) {
      // 客户端中断等导致的写入异常，忽略；务必关闭响应避免客户端挂起
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> close() => _server.close(force: true);
}
