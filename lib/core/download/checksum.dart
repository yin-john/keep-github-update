/// 校验文件定位与哈希解析（纯函数，便于复用与测试）
library;

import '../config/models.dart';
import '../github/release_model.dart';

/// 在 release 资产中查找与目标产物对应的校验文件。
/// 优先使用 rule.checksumRegex（若存在），否则按默认扩展名推断：
///   <产物名>.sha256 / .sha256sum / .sha256.txt（sha256）
///   <产物名>.md5 / .md5sum / .md5.txt（md5）
/// 以及包含产物名与扩展名的任意文件（如 sha256sums.txt）。
Asset? findChecksumAsset(Release release, Asset target, AssetRule rule) {
  final candidates = release.assets.where((a) => a.name != target.name);

  if (rule.checksumRegex != null) {
    try {
      final re = RegExp(rule.checksumRegex!, caseSensitive: false);
      for (final a in candidates) {
        if (re.hasMatch(a.name)) return a;
      }
    } catch (_) {
      // 非法正则忽略
    }
  }

  final exts = rule.checksumType == ChecksumType.sha256
      ? const ['sha256', 'sha256sum', 'sha256.txt']
      : const ['md5', 'md5sum', 'md5.txt'];

  for (final ext in exts) {
    final name = '${target.name}.$ext';
    for (final a in candidates) {
      if (a.name.toLowerCase() == name.toLowerCase()) return a;
    }
  }

  for (final ext in exts) {
    final re = RegExp(
      '${RegExp.escape(target.name)}.*\\.${RegExp.escape(ext)}\$',
      caseSensitive: false,
    );
    for (final a in candidates) {
      if (re.hasMatch(a.name)) return a;
    }
  }

  return null;
}

/// 从校验文件内容中解析出哈希值。
/// 兼容常见格式：
///   <hash>
///   <hash>  <filename>
///   <hash> *<filename>
///   <filename>: <algo> = <hash>
String? parseChecksum(String content, ChecksumType type) {
  final expectedLen = type == ChecksumType.sha256 ? 64 : 32;
  final hexRe = RegExp('[0-9a-fA-F]{$expectedLen}');
  for (final line in content.split(RegExp(r'[\r\n]+'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final m = hexRe.firstMatch(trimmed);
    if (m != null) return m.group(0)!.toLowerCase();
  }
  return null;
}
