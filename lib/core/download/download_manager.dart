/// 下载管理器：支持进度回调、多线程分块下载、SHA256 校验、可中断。
///
/// 使用 dio 自带的 `download()` 落盘（不手动消费流，兼容镜像/重定向场景）。
library;

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import '../config/models.dart';
import '../log/app_log.dart';

typedef ProgressCallback = void Function(int received, int total);

/// 下载被用户中断
class DownloadCancelled implements Exception {
  DownloadCancelled([this.message = '下载已中断']);
  final String message;
  @override
  String toString() => message;
}

class DownloadManager {

  DownloadManager({Dio? dio, this.threads = 1})
      : dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              headers: const {'User-Agent': 'grku'}, // 部分镜像对无 UA 请求返回空响应
            ));
  final Dio dio;

  /// 下载线程数（>1 时尝试分块并发；服务器不支持 Range 时自动回退单线程）
  final int threads;

  /// 下载到 savePath；[cancelToken] 可中断；[expectedChecksum] 非空时校验。
  Future<File> download(
    String url,
    String savePath, {
    ProgressCallback? onProgress,
    String? expectedChecksum,
    ChecksumType checksumType = ChecksumType.sha256,
    CancelToken? cancelToken,
  }) async {
    if (threads > 1) {
      try {
        return await _downloadMulti(url, savePath, onProgress,
            expectedChecksum, checksumType, cancelToken);
      } on DownloadCancelled {
        rethrow;
      } catch (e) {
        AppLog.warn('多线程下载失败，回退单线程: $e');
      }
    }
    return _downloadSingle(
        url, savePath, onProgress, expectedChecksum, checksumType, cancelToken);
  }

  // ---------------- 单线程 ----------------

  Future<File> _downloadSingle(
    String url,
    String savePath,
    ProgressCallback? onProgress,
    String? expectedChecksum,
    ChecksumType checksumType,
    CancelToken? cancelToken,
  ) async {
    // 使用 .part 支持「暂停/续传」：中断时保留已下载部分
    final part = File('$savePath.part');
    await part.parent.create(recursive: true);
    var start = await part.exists() ? await part.length() : 0;
    try {
      if (start > 0) {
        // 续传：先下到临时文件再追加到 .part
        final resume = File('$savePath.resume');
        if (await resume.exists()) await resume.delete();
        final resp = await dio.download(
          url,
          resume.path,
          onReceiveProgress: (rc, t) =>
              onProgress?.call(start + rc, t > 0 ? start + t : start + rc),
          cancelToken: cancelToken,
          options: Options(
            followRedirects: true,
            validateStatus: (_) => true,
            headers: {'Range': 'bytes=$start-'},
          ),
        );
        if (resp.statusCode == 206) {
          final bytes = await resume.readAsBytes();
          await part.writeAsBytes(bytes, mode: FileMode.append);
          if (await resume.exists()) await resume.delete();
        } else {
          // 服务器不支持续传：丢弃已下载部分，从头下载
          if (await resume.exists()) await resume.delete();
          if (await part.exists()) await part.delete();
          start = 0;
        }
      }
      if (start == 0) {
        if (await part.exists()) await part.delete();
        await dio.download(
          url,
          part.path,
          onReceiveProgress: (rc, t) =>
              onProgress?.call(rc, t > 0 ? t : rc),
          cancelToken: cancelToken,
          deleteOnError: false, // 保留已下载部分以便续传
          options: Options(followRedirects: true),
        );
      }
      AppLog.info('下载完成 → $savePath（起点 $start 字节）');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw DownloadCancelled(); // 保留 .part，下次可续传
      }
      rethrow;
    }
    await _verify(part, expectedChecksum, checksumType);
    return _finalize(part, savePath);
  }

  // ---------------- 多线程分块 ----------------

  Future<File> _downloadMulti(
    String url,
    String savePath,
    ProgressCallback? onProgress,
    String? expectedChecksum,
    ChecksumType checksumType,
    CancelToken? cancelToken,
  ) async {
    final head = await dio.head<void>(
      url,
      options: Options(followRedirects: true, validateStatus: (_) => true),
      cancelToken: cancelToken,
    );
    final status = head.statusCode ?? 0;
    final len = int.tryParse(head.headers.value('content-length') ?? '');
    final acceptRanges =
        (head.headers.value('accept-ranges') ?? '').toLowerCase();
    if (len == null || len <= 0 || acceptRanges != 'bytes') {
      throw Exception(
          '服务器不支持分块下载（status=$status length=$len accept-ranges=$acceptRanges）');
    }

    final n = threads.clamp(2, 16);
    final chunkSize = (len / n).ceil();
    final parts = <File>[];
    final received = List<int>.filled(n, 0);
    void report() =>
        onProgress?.call(received.fold<int>(0, (a, b) => a + b), len);

    try {
      final futures = <Future<void>>[];
      for (var i = 0; i < n; i++) {
        final start = i * chunkSize;
        if (start >= len) break;
        final end = (start + chunkSize - 1) < (len - 1)
            ? (start + chunkSize - 1)
            : (len - 1);
        final part = File('$savePath.part$i');
        parts.add(part);
        final idx = i;
        futures.add(dio
            .download(
              url,
              part.path,
              options: Options(
                followRedirects: true,
                headers: {'Range': 'bytes=$start-$end'},
              ),
              cancelToken: cancelToken,
              onReceiveProgress: (rc, _) {
                received[idx] = rc;
                report();
              },
            )
            .then((_) {}));
      }
      await Future.wait(futures);

      // 合并分块
      final target = File(savePath);
      await target.parent.create(recursive: true);
      if (await target.exists()) await target.delete();
      final sink = target.openWrite();
      for (final p in parts) {
        await sink.addStream(p.openRead());
      }
      await sink.flush();
      await sink.close();

      final actualLen = await target.length();
      if (actualLen != len) {
        throw Exception('分块合并大小不符：$actualLen != $len');
      }
      await _verify(target, expectedChecksum, checksumType);
      return target;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw DownloadCancelled();
      rethrow;
    } finally {
      for (final p in parts) {
        if (await p.exists()) {
          try {
            await p.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _verify(
      File f, String? expectedChecksum, ChecksumType type) async {
    if (expectedChecksum == null) return;
    final actual = await _hash(f, type);
    if (actual != expectedChecksum.toLowerCase()) {
      await f.delete();
      throw Exception('校验失败：期望 $expectedChecksum，实际 $actual');
    }
  }

  Future<File> _finalize(File part, String savePath) async {
    final target = File(savePath);
    if (await target.exists()) await target.delete();
    await part.rename(savePath);
    return target;
  }

  /// 下载文本（用于读取校验文件内容）
  Future<String> downloadText(String url) async {
    final resp = await dio.get<String>(
      url,
      options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (_) => true),
    );
    if ((resp.statusCode ?? 0) != 200) {
      throw Exception('获取文本失败：HTTP ${resp.statusCode}');
    }
    return resp.data ?? '';
  }

  Future<String> _hash(File f, ChecksumType type) async {
    final bytes = await f.readAsBytes();
    final digest =
        type == ChecksumType.md5 ? md5.convert(bytes) : sha256.convert(bytes);
    return digest.toString();
  }
}
