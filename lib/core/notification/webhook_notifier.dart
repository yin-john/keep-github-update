/// Webhook 通知：向配置 URL POST JSON，可带 HMAC-SHA256 签名
library;

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class WebhookNotifier {

  WebhookNotifier({Dio? dio}) : dio = dio ?? Dio();
  final Dio dio;

  Future<void> post(
    String url,
    Map<String, dynamic> payload, {
    String? secret,
    Map<String, String>? headers,
  }) async {
    final body = jsonEncode(payload);
    final h = <String, String>{
      'Content-Type': 'application/json',
      if (headers != null) ...headers,
    };
    if (secret != null && secret.isNotEmpty) {
      final mac = Hmac(sha256, utf8.encode(secret));
      final sig = mac.convert(utf8.encode(body)).toString();
      h['X-GRKU-Signature'] = 'sha256=$sig';
    }
    try {
      await dio.post(url, data: body, options: Options(headers: h));
    } catch (e) {
      print('Webhook 发送失败（不影响主流程）: $e');
    }
  }
}
