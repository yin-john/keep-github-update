/// 设计稿 sidecar（`<Name>.design.json`）的读写。
///
/// `.dart` 是单向输出，无法从格式化后的源码反推组件树；没有 sidecar 就无法再次
/// 打开编辑。sidecar 与 `.dart` 同目录，JSON 不会被 analyzer 分析，零风险。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'project.dart';

/// sidecar 结构版本号（树结构变更时递增）。
const int kDesignVersion = 1;

const String _designSuffix = '.design.json';

/// 设计稿读写。
class DesignStore {
  DesignStore(this.root);

  final Directory root;

  /// 列出已有设计稿名（字母序）。
  List<String> list() {
    final dir = generatedDir(root);
    if (!dir.existsSync()) {
      return <String>[];
    }
    final names = <String>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final base = p.basename(entity.path);
      if (base.endsWith(_designSuffix)) {
        names.add(base.substring(0, base.length - _designSuffix.length));
      }
    }
    names.sort();
    return names;
  }

  /// 读取设计稿；不存在返回 `null`。
  Map<String, Object?>? read(String name) {
    final file = resolveDesignTarget(root, name);
    if (!file.existsSync()) {
      return null;
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('设计稿格式非法');
    }
    return decoded.cast<String, Object?>();
  }

  /// 写入设计稿。
  void write(String name, Object? tree) {
    ensureGeneratedDir(root);
    final file = resolveDesignTarget(root, name);
    final payload = <String, Object?>{
      'version': kDesignVersion,
      'name': name,
      'tree': tree,
    };
    file.writeAsStringSync('${jsonEncode(payload)}\n');
  }

  /// 删除设计稿；文件不存在返回 `false`。
  bool delete(String name) {
    final file = resolveDesignTarget(root, name);
    if (!file.existsSync()) {
      return false;
    }
    file.deleteSync();
    return true;
  }
}
