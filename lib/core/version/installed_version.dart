/// 已安装版本的解析与比较（设备侧真实版本，而非本应用记录）。
///
/// - Android：Magisk/KernelSU 模块的 `module.prop`、已装应用的 `dumpsys package`
/// - Windows/Linux：安装目录下的版本记录文件
library;

import 'package:path/path.dart' as p;

/// 更新完成后写入目标目录的版本记录文件名
const String versionFileName = 'grku_version.txt';

/// 归一化版本号：统一小写、去掉前导 v 与全部空白
String normalizeVersion(String? v) {
  if (v == null) return '';
  var s = v.trim().toLowerCase();
  s = s.replaceFirst(RegExp(r'^v'), '');
  s = s.replaceAll(RegExp(r'\s+'), '');
  return s;
}

/// 提取版本号核心（第一段数字点串），如 `app-v1.2.3-beta` → `1.2.3`
String versionCore(String? v) {
  if (v == null) return '';
  final m = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(v);
  return m?.group(1) ?? '';
}

List<int> _parts(String? v) => versionCore(v)
    .split('.')
    .where((e) => e.isNotEmpty)
    .map((e) => int.tryParse(e) ?? 0)
    .toList();

/// 比较两个版本号：a<b 返回负数，相等返回 0，a>b 返回正数。
/// 数字核心相同即视为同一版本（`1.2` == `1.2.0`，忽略 -beta 等后缀差异）。
int compareVersions(String? a, String? b) {
  final ca = versionCore(a);
  final cb = versionCore(b);
  if (ca.isEmpty || cb.isEmpty) {
    final na = normalizeVersion(a);
    final nb = normalizeVersion(b);
    if (na == nb) return 0;
    return na.compareTo(nb) < 0 ? -1 : 1;
  }
  final pa = _parts(a);
  final pb = _parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

/// 已安装版本与 release tag 是否视为同一版本（如 `1.2.3` vs `v1.2.3`、`1.2` vs `1.2.0`）
bool versionMatches(String? installed, String? tag) {
  final a = normalizeVersion(installed);
  final b = normalizeVersion(tag);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (versionCore(installed).isEmpty || versionCore(tag).isEmpty) return false;
  return compareVersions(installed, tag) == 0;
}

/// 已安装版本与 release tag 是否同一版本，兼容 LSPosed 模块仓库的
/// `<versionCode>-<versionName>` tag 格式（如 tag `20950-1.3.4`，
/// 应用 versionName 只有 `1.3.4`）——取最后一个 `-` 之后的片段再比对。
bool versionMatchesTag(String? installed, String? tag) {
  if (versionMatches(installed, tag)) return true;
  final t = tag ?? '';
  final dash = t.lastIndexOf('-');
  if (dash <= 0 || dash >= t.length - 1) return false;
  return versionMatches(installed, t.substring(dash + 1));
}

/// tag 是否比已安装版本更新
bool versionIsNewer(String? tag, String? installed) {
  if (installed == null || installed.isEmpty) return true;
  return compareVersions(tag, installed) > 0;
}

/// Magisk / KernelSU 模块的 module.prop
class ModuleProp {

  const ModuleProp({
    this.id = '',
    this.name = '',
    this.version = '',
    this.versionCode = '',
    this.updateJson = '',
  });
  final String id;
  final String name;
  final String version;
  final String versionCode;
  final String updateJson;

  /// 优先 version，其次 versionCode
  String get display => version.isNotEmpty ? version : versionCode;
}

/// 解析 module.prop 文本
ModuleProp parseModuleProp(String content) {
  String pick(String key) {
    final m = RegExp('^\\s*$key\\s*=\\s*(.*)\$', multiLine: true)
        .firstMatch(content);
    return m?.group(1)?.trim() ?? '';
  }

  return ModuleProp(
    id: pick('id'),
    name: pick('name'),
    version: pick('version'),
    versionCode: pick('versionCode'),
    updateJson: pick('updateJson'),
  );
}

/// 解析 shell 输出：每段以 `@@<moduleId>` 开头，其后为该模块的 module.prop 内容
Map<String, String> parseModuleSections(String raw) {
  final out = <String, String>{};
  String? cur;
  final buf = StringBuffer();
  void flush() {
    if (cur != null) out[cur] = buf.toString();
    buf.clear();
  }

  for (final line in raw.split('\n')) {
    if (line.startsWith('@@')) {
      flush();
      cur = line.substring(2).trim();
      continue;
    }
    if (cur != null) buf.writeln(line);
  }
  flush();
  return out;
}

/// 从设备已装模块中找出与仓库对应的模块 ID
///
/// 优先顺序：显式 moduleId → updateJson 指向该仓库 → id 与仓库名一致 → name 与仓库名一致
String? matchModuleId(
  Map<String, String> modules, {
  String? moduleId,
  required String owner,
  required String repo,
}) {
  if (modules.isEmpty) return null;
  if (moduleId != null && moduleId.isNotEmpty) {
    if (modules.containsKey(moduleId)) return moduleId;
    final lower = moduleId.toLowerCase();
    for (final k in modules.keys) {
      if (k.toLowerCase() == lower) return k;
    }
    return null;
  }

  final slug = normalizeVersion(repo);
  final full = '${normalizeVersion(owner)}/${normalizeVersion(repo)}';

  // 1) updateJson 指向该仓库（最可靠）
  for (final e in modules.entries) {
    final u = parseModuleProp(e.value).updateJson.toLowerCase();
    if (u.isEmpty) continue;
    if (u.contains('github.com/$owner/$repo'.toLowerCase()) ||
        u.contains('github.com/$full') ||
        u.contains('/$owner/$repo'.toLowerCase())) {
      return e.key;
    }
  }

  // 2) 模块 id / name 与仓库名一致
  for (final e in modules.entries) {
    final prop = parseModuleProp(e.value);
    final id = prop.id.isNotEmpty ? prop.id : e.key;
    if (normalizeVersion(id) == slug) return e.key;
    if (normalizeVersion(prop.name) == slug) return e.key;
  }
  return null;
}

/// 从设备已装应用版本表中猜出该仓库对应的包名（依据已记录的版本号反查）
String? guessPackageName(
  Map<String, String> versions, {
  String? installedTag,
  String? exclude,
}) {
  if (installedTag == null || installedTag.isEmpty) return null;
  final hits = versions.entries
      .where(
          (e) => e.key != exclude && versionMatchesTag(e.value, installedTag))
      .toList();
  return hits.length == 1 ? hits.first.key : null;
}

/// 解析 `dumpsys package` 输出中的 包名 → versionName
Map<String, String> parsePackageVersions(String dump) {
  final out = <String, String>{};
  final pkgRe = RegExp(r'Package \[([^\]]+)\]');
  final verRe = RegExp(r'^\s*versionName=(\S+)');
  String? cur;
  for (final line in dump.split('\n')) {
    final m = pkgRe.firstMatch(line);
    if (m != null) {
      cur = m.group(1);
      continue;
    }
    if (cur == null) continue;
    final v = verRe.firstMatch(line);
    if (v != null && !out.containsKey(cur)) {
      out[cur] = v.group(1)!;
    }
  }
  return out;
}

/// 读取版本记录文件（grku_version.txt）中的 version 字段
String? parseVersionFile(String content) {
  final m = RegExp(r'^\s*version\s*:\s*(.+)$', multiLine: true)
      .firstMatch(content);
  final v = m?.group(1)?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// 版本记录文件的路径
String versionFilePath(String installDir) => p.join(installDir, versionFileName);
