import 'dart:io';

/// 删除临时目录（测试收尾用）。
///
/// Windows 上被取消的下载其文件句柄可能还没释放，直接删除会抛
/// `PathAccessException: ... being used by another process, errno = 32`，
/// 因此这里重试若干次并最终忽略失败——收尾清理不该让测试失败。
Future<void> deleteDirQuietly(Directory dir, {int tries = 12}) async {
  for (var i = 0; i < tries; i++) {
    if (!await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
      return;
    } catch (_) {
      await Future<void>.delayed(Duration(milliseconds: 40 * (i + 1)));
    }
  }
}
