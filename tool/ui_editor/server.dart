/// 本地编辑器 HTTP 服务：静态资源 + 组件目录 + 预览 + 保存。
///
/// 安全模型（本进程会写盘）：
/// 1. 只绑 `127.0.0.1`；
/// 2. 每次运行随机 token，前端以 `X-Editor-Token` 头发送；
/// 3. 自定义头 + 从不发送 CORS 头 + 拒绝 `OPTIONS`，天然挡 CSRF；
/// 4. 校验 `Host` 头，防 DNS rebinding；
/// 5. POST 要求 `application/json`，请求体有上限；
/// 6. 静态资源做目录穿越防护。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'codegen.dart';
import 'dart_emitter.dart';
import 'design_store.dart';
import 'format.dart';
import 'project.dart';
import 'widget_catalog.dart';

/// 请求体上限（2 MB）。
const int _maxBodyBytes = 2 * 1024 * 1024;

/// API 层错误（带 HTTP 状态码）。
class ApiException implements Exception {
  ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'ApiException($status): $message';
}

/// 编辑器服务。
class EditorServer {
  EditorServer._(
    this._server,
    this.root,
    this.assetsDir,
    this.token, {
    required bool formatOnSave,
  })  : _formatOnSave = formatOnSave,
        _done = Completer<void>();

  /// 绑定 `127.0.0.1`（`port` 为 0 时由系统分配）并开始监听。
  static Future<EditorServer> start({
    required Directory rootDir,
    required Directory assetsDir,
    required String token,
    int port = 0,
    bool formatOnSave = true,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final editor = EditorServer._(
      server,
      rootDir,
      assetsDir,
      token,
      formatOnSave: formatOnSave,
    );
    unawaited(editor._serve());
    return editor;
  }

  final HttpServer _server;
  final Directory root;
  final Directory assetsDir;
  final String token;
  final bool _formatOnSave;

  // 延迟初始化：构造期不能引用其它实例字段。
  late final DesignStore _store = DesignStore(root);
  final Completer<void> _done;

  /// 实际监听端口。
  int get port => _server.port;

  /// 服务停止时完成。
  Future<void> get done => _done.future;

  /// 关闭服务。
  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    try {
      await for (final request in _server) {
        try {
          await _dispatch(request);
        } on ApiException catch (e) {
          await _safeJson(
              request, e.status, <String, Object?>{'error': e.message});
        } catch (e) {
          await _safeJson(
              request, 500, <String, Object?>{'error': '内部错误：$e'});
        }
      }
    } on Object {
      // 服务流异常（例如端口被强制关闭）——开发期工具，忽略即可。
    } finally {
      if (!_done.isCompleted) {
        _done.complete();
      }
    }
  }

  Future<void> _dispatch(HttpRequest request) async {
    if (!_hostAllowed(request)) {
      throw ApiException(403, 'Host 头不被允许');
    }
    if (request.method == 'OPTIONS') {
      // 明确拒绝预检，跨站页面因此无法构造带自定义头的请求。
      throw ApiException(405, '不支持 OPTIONS');
    }

    final path = request.uri.path;

    if (request.method == 'GET') {
      final relative = _staticTargetFor(path);
      if (relative != null) {
        await _serveStatic(request.response, relative);
        return;
      }
    }

    if (path == '/api/health') {
      await _sendJson(request.response, 200, <String, Object?>{'ok': true});
      return;
    }

    if (!path.startsWith('/api/')) {
      throw ApiException(404, '未找到 $path');
    }
    if (!_tokenValid(request)) {
      throw ApiException(401, '缺少或错误的 X-Editor-Token');
    }

    if (path == '/api/palette') {
      _requireMethod(request.method, 'GET');
      await _sendJson(
        request.response,
        200,
        kCatalog.map((spec) => spec.toJson()).toList(),
      );
      return;
    }
    if (path == '/api/preview') {
      _requireMethod(request.method, 'POST');
      final body = await _readJsonBody(request);
      final tree = UiNode.fromJson(body['tree']);
      final code = generateSource(className: 'Preview', root: tree);
      await _sendJson(request.response, 200, <String, Object?>{'code': code});
      return;
    }
    if (path == '/api/save') {
      _requireMethod(request.method, 'POST');
      final body = await _readJsonBody(request);
      await _handleSave(request.response, body);
      return;
    }
    if (path == '/api/designs') {
      _requireMethod(request.method, 'GET');
      await _sendJson(request.response, 200, _store.list());
      return;
    }
    if (path == '/api/design') {
      await _handleDesign(request);
      return;
    }

    throw ApiException(404, '未找到 $path');
  }

  // ————————————— 保存 —————————————

  Future<void> _handleSave(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final name = body['name'];
    if (name is! String) {
      throw ApiException(400, '缺少 name');
    }
    final nameError = validateClassName(name);
    if (nameError != null) {
      throw ApiException(400, nameError);
    }
    final target = resolveGeneratedTarget(root, name);
    if (target.existsSync() && body['overwrite'] != true) {
      throw ApiException(409, '$name.dart 已存在；确认覆盖请带 overwrite: true');
    }

    final tree = UiNode.fromJson(body['tree']);
    final source = generateSource(className: name, root: tree);
    ensureGeneratedDir(root);
    target.writeAsStringSync(source);
    _store.write(name, body['tree']);

    var formatted = false;
    if (_formatOnSave) {
      formatted = await tryFormatFile(target);
    }
    final code = formatted ? target.readAsStringSync() : source;
    await _sendJson(response, 200, <String, Object?>{
      'path': target.path,
      'code': code,
      'formatted': formatted,
    });
  }

  // ————————————— 设计稿 —————————————

  Future<void> _handleDesign(HttpRequest request) async {
    final name = request.uri.queryParameters['name'];
    if (name == null || name.isEmpty) {
      throw ApiException(400, '缺少 name 查询参数');
    }
    final nameError = validateClassName(name);
    if (nameError != null) {
      throw ApiException(400, nameError);
    }

    if (request.method == 'GET') {
      final design = _store.read(name);
      if (design == null) {
        throw ApiException(404, '设计稿不存在：$name');
      }
      await _sendJson(request.response, 200, design);
      return;
    }
    if (request.method == 'DELETE') {
      final removed = _store.delete(name);
      await _sendJson(request.response, 200, <String, Object?>{'ok': removed});
      return;
    }
    throw ApiException(405, '仅支持 GET / DELETE');
  }

  // ————————————— 静态资源 —————————————

  String? _staticTargetFor(String path) {
    if (path == '/' || path == '/index.html') {
      return 'index.html';
    }
    if (path == '/app.js') {
      return 'app.js';
    }
    if (path == '/style.css') {
      return 'style.css';
    }
    return null;
  }

  Future<void> _serveStatic(HttpResponse response, String relative) async {
    final base = p.normalize(assetsDir.absolute.path);
    final target = p.normalize(p.join(base, relative));
    if (!p.isWithin(base, target)) {
      throw ApiException(403, '非法资源路径');
    }
    final file = File(target);
    if (!file.existsSync()) {
      throw ApiException(404, '未找到 $relative');
    }
    response.statusCode = 200;
    response.headers.contentType = _contentTypeFor(target);
    await file.openRead().pipe(response);
  }

  // ————————————— 鉴权与请求解析 —————————————

  bool _hostAllowed(HttpRequest request) {
    final host = request.headers.host;
    if (host != '127.0.0.1' && host != 'localhost' && host != '::1') {
      return false;
    }
    final port = request.headers.port;
    return port == null || port == _server.port;
  }

  bool _tokenValid(HttpRequest request) {
    final provided = request.headers.value('x-editor-token');
    if (provided == null) {
      return false;
    }
    return _constantTimeEquals(provided, token);
  }

  void _requireMethod(String actual, String expected) {
    if (actual != expected) {
      throw ApiException(405, '仅支持 $expected');
    }
  }

  Future<Map<String, Object?>> _readJsonBody(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType == null || contentType.mimeType != 'application/json') {
      throw ApiException(415, 'Content-Type 必须是 application/json');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > _maxBodyBytes) {
        throw ApiException(413, '请求体过大（上限 ${_maxBodyBytes ~/ 1024} KB）');
      }
    }
    if (builder.isEmpty) {
      throw ApiException(400, '请求体为空');
    }
    final decoded = _decodeJson(builder.takeBytes());
    if (decoded is! Map) {
      throw ApiException(400, '请求体必须是 JSON 对象');
    }
    return decoded.cast<String, Object?>();
  }

  Future<void> _sendJson(
    HttpResponse response,
    int status,
    Object? payload,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }

  Future<void> _safeJson(
    HttpRequest request,
    int status,
    Object? payload,
  ) async {
    try {
      await _sendJson(request.response, status, payload);
    } on Object {
      // 响应可能已开始写出（如静态文件传输中断），忽略二次写入失败。
    }
  }
}

Object? _decodeJson(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    throw ApiException(400, 'JSON 解析失败：${e.message}');
  }
}

bool _constantTimeEquals(String a, String b) {
  final left = utf8.encode(a);
  final right = utf8.encode(b);
  if (left.length != right.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < left.length; i++) {
    diff |= left[i] ^ right[i];
  }
  return diff == 0;
}

// 注意：ContentType 是**工厂构造器**，不能加 const。
ContentType _contentTypeFor(String path) {
  if (path.endsWith('.html')) {
    return ContentType('text', 'html', charset: 'utf-8');
  }
  if (path.endsWith('.js')) {
    return ContentType('application', 'javascript', charset: 'utf-8');
  }
  if (path.endsWith('.css')) {
    return ContentType('text', 'css', charset: 'utf-8');
  }
  if (path.endsWith('.svg')) {
    return ContentType('image', 'svg+xml', charset: 'utf-8');
  }
  if (path.endsWith('.json')) {
    return ContentType.json;
  }
  return ContentType.binary;
}
