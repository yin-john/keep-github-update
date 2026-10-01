/// 项目根目录解析、web 资源定位、类名校验与生成文件写入沙箱。
///
/// 本文件属于开发期工具（`tool/`），**不得 import `package:flutter/*`**：
/// 它跑在 `dart run` 下，没有 `dart:ui`。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// 目标工程包名（用于在向上查找时优先命中本仓库）。
const String kPackageName = 'github_releases_keep_update';

/// 生成目录（相对项目根），所有写入都被限制在此目录内。
const List<String> kGeneratedDirSegments = <String>['lib', 'ui', 'generated'];

/// 从 [start] 向上查找项目根目录。
///
/// 命中「含 `pubspec.yaml` 且 `name:` 为 [kPackageName]」的目录即返回；
/// 找不到精确命中时退化为「最近的含 `pubspec.yaml` 的目录」；
/// 两者都没有则抛 [StateError]。
Directory findProjectRoot(Directory start) {
  var dir = start.absolute;
  Directory? nearest;
  for (var i = 0; i < 40; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      nearest ??= dir;
      final content = pubspec.readAsStringSync();
      final pattern =
          RegExp('^name:\\s*$kPackageName\\s*\$', multiLine: true);
      if (pattern.hasMatch(content)) {
        return dir;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  if (nearest != null) {
    return nearest;
  }
  throw StateError('未能在 ${start.path} 之上找到 pubspec.yaml，'
      '请在项目目录内运行本工具。');
}

/// 定位编辑器静态资源目录（含 `index.html`）。
///
/// `Platform.script` 在不同调用方式下不可靠（snapshot / AOT 下指向快照或 exe），
/// 因此用回退链逐个尝试，命中即返回；全部失败则抛出带指引的 [StateError]。
Directory resolveWebAssetsDir() {
  final candidates = <Directory>[];

  final override = Platform.environment['UI_EDITOR_ASSETS'];
  if (override != null && override.isNotEmpty) {
    candidates.add(Directory(override));
  }

  try {
    final script = Platform.script;
    if (script.scheme == 'file') {
      candidates
        ..add(Directory.fromUri(script.resolve('ui_editor/web/')))
        ..add(Directory.fromUri(script.resolve('web/')));
    }
  } on Object {
    // Platform.script 不可用时忽略，继续尝试其余候选
  }

  candidates.add(
      Directory(p.join(Directory.current.path, 'tool', 'ui_editor', 'web')));

  for (final dir in candidates) {
    if (dir.path.isEmpty) {
      continue;
    }
    if (File(p.join(dir.path, 'index.html')).existsSync()) {
      return dir;
    }
  }

  throw StateError('找不到编辑器 web 资源（index.html）。'
      '请设置环境变量 UI_EDITOR_ASSETS=<tool/ui_editor/web 的绝对路径>。');
}

/// 校验类名，合法返回 `null`，否则返回错误信息。
///
/// 规则：`^[A-Z][A-Za-z0-9]*$`、长度 ≤ 64、非 Dart 保留字。
/// 该规则本身即排除了 `/`、`\`、`.`、`$`，使目录穿越在结构上不可能。
String? validateClassName(String name) {
  if (name.isEmpty) {
    return '类名不能为空';
  }
  if (name.length > 64) {
    return '类名过长（最多 64 字符）';
  }
  if (!RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(name)) {
    return '类名需以大写字母开头，且只含字母与数字';
  }
  if (dartKeywords.contains(name)) {
    return '类名不能是 Dart 保留字';
  }
  return null;
}

/// 生成目录（不存在时不创建）。
Directory generatedDir(Directory root) =>
    Directory(p.joinAll(<String>[root.path, ...kGeneratedDirSegments]));

/// 生成目录（按需创建）。
Directory ensureGeneratedDir(Directory root) {
  final dir = generatedDir(root);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

/// 解析 `<Name>.dart` 的写入目标，并做沙箱校验。
///
/// 类名非法或目标逃逸出生成目录时抛 [ArgumentError]。
File resolveGeneratedTarget(Directory root, String name) {
  final error = validateClassName(name);
  if (error != null) {
    throw ArgumentError(error);
  }
  return _resolveInGenerated(root, '$name.dart');
}

/// 解析 `<Name>.design.json` 的写入目标，并做沙箱校验。
File resolveDesignTarget(Directory root, String name) {
  final error = validateClassName(name);
  if (error != null) {
    throw ArgumentError(error);
  }
  return _resolveInGenerated(root, '$name.design.json');
}

File _resolveInGenerated(Directory root, String fileName) {
  final base = p.normalize(generatedDir(root).absolute.path);
  final target = p.normalize(p.join(base, fileName));
  // 双保险：类名校验已排除穿越字符，这里再确认目标仍在沙箱内。
  if (!p.isWithin(base, target)) {
    throw ArgumentError('目标路径越界：$target');
  }
  return File(target);
}

/// Dart 保留字（用于拒绝把保留字当类名）。
const Set<String> dartKeywords = <String>{
  'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
  'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
  'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
  'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
  'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
  'late', 'library', 'mixin', 'new', 'null', 'on', 'operator', 'part',
  'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
  'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef',
  'var', 'void', 'when', 'while', 'with', 'yield',
};
