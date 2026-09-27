/// 配置仓库：软件配置（config.yaml）与仓库配置（repos.yaml）分开存放。
///
/// - configVersion 4 起拆分为两个文件，向上兼容：
///   每次启动都会检测旧版单文件配置（v1–v3，软件配置里带 repos），
///   自动拆分并转换为 v4，原文件备份为 `config.yaml.bak`（仅首次）。
/// - 导入/导出仍使用单个合并文件（软件配置 + repos），便于分享与回滚；
///   导入旧版文件时同样会自动转换为 v4。
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';
import '../config/models.dart';
import '../log/app_log.dart';

/// 配置读写的可预期错误（路径为空、文件不存在/为空、内容非法等）
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ConfigRepository {
  ConfigRepository(this.configPath);
  final String configPath;

  /// 仓库配置文件（与软件配置同目录、分开存放）
  String get reposPath => p.join(p.dirname(configPath), 'repos.yaml');

  static const defaultFileName = 'grku_config.yaml';

  AppConfig? _cache;

  /// 从默认路径加载（应用启动时调用；会自动检测并转换旧版配置）
  Future<AppConfig> load() async {
    final appFile = File(configPath);
    final reposFile = File(reposPath);

    // —— 旧版单文件配置（v1–v3：软件配置里带 repos）→ 拆分为 v4 ——
    if (await appFile.exists()) {
      final content = await appFile.readAsString();
      if (content.trim().isNotEmpty) {
        Object? decoded;
        try {
          decoded = _decode(content);
        } catch (_) {
          decoded = null; // 解析失败时按后续流程原样读取，避免启动失败
        }
        if (decoded is Map && decoded['repos'] is List) {
          await _migrateLegacy(Map<String, dynamic>.from(decoded), appFile);
        }
      }
    }

    // —— 组合：软件配置（config.yaml）+ 仓库配置（repos.yaml）——
    var cfg = const AppConfig(
      webhook:
          WebhookConfig(enabled: false, url: '', events: NotificationEvent.values),
    );
    if (await appFile.exists()) {
      final content = await appFile.readAsString();
      if (content.trim().isNotEmpty) {
        cfg = AppConfig.fromJson(_asMap(_decode(content)));
      }
    }
    if (await reposFile.exists()) {
      final content = await reposFile.readAsString();
      if (content.trim().isNotEmpty) {
        final m = _asMap(_decode(content));
        cfg = cfg.copyWith(
          repos: (m['repos'] as List? ?? const [])
              .map((e) => RepoConfig.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
        );
      }
    }
    _cache = cfg;
    AppLog.configure(cfg.loggingEnabled);
    return cfg;
  }

  /// 从任意路径（YAML/JSON）加载一份配置（用于导入/预览）。
  /// 路径为空、文件不存在、内容为空或不是对象时抛 [ConfigException]。
  Future<AppConfig> loadFrom(String path) async {
    final target = path.trim();
    if (target.isEmpty) {
      throw ConfigException('配置文件路径为空');
    }
    var file = File(target);
    // 未写扩展名时尝试常见后缀，便于用户少打字
    if (!await file.exists() && p.extension(target).isEmpty) {
      for (final ext in const ['.yaml', '.yml', '.json']) {
        final alt = File('$target$ext');
        if (await alt.exists()) {
          file = alt;
          break;
        }
      }
    }
    if (!await file.exists()) {
      throw ConfigException('配置文件不存在：$target');
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      throw ConfigException('配置文件是空的：${file.path}');
    }
    final Object? decoded;
    try {
      decoded = _decode(content);
    } catch (e) {
      throw ConfigException('配置文件解析失败：$e');
    }
    if (decoded is! Map) {
      throw ConfigException('配置内容格式不正确（应为 YAML/JSON 对象）：${file.path}');
    }
    return AppConfig.fromJson(Map<String, dynamic>.from(decoded));
  }

  /// 按路径串行化写入，避免并发保存把文件写坏（跨实例共享）
  static final Map<String, Future<void>> _writeLocks = {};

  Future<void> _withLock(Future<void> Function() fn) {
    final prev = _writeLocks[configPath] ?? Future<void>.value();
    final next = prev.then((_) => fn());
    _writeLocks[configPath] = next.catchError((_) {});
    return next;
  }

  /// 保存到默认位置：软件配置 config.yaml + 仓库配置 repos.yaml（均为 v4）
  Future<void> save(AppConfig config) {
    return _withLock(() async {
      await _writeLive(config);
      _cache = config;
    });
  }

  /// 保存到指定路径（导出/交换用）：单个合并文件（软件配置 + repos），v4
  Future<void> saveTo(AppConfig config, String path) {
    final target = path.trim();
    if (target.isEmpty) {
      throw ConfigException('保存路径为空，已取消写入');
    }
    return _withLock(() async {
      final json = _appJson(config);
      json['repos'] = config.repos.map((e) => e.toJson()).toList();
      await _writeFile(File(target), json);
      AppLog.configure(config.loggingEnabled);
    });
  }

  /// 导入：用另一份文件内容覆盖当前配置。
  ///
  /// 默认拒绝用「不含任何仓库」或校验不通过的配置覆盖，避免把现有配置清空；
  /// 确需导入空配置时传 [allowEmpty] = true。旧版文件导入后自动转换为 v4。
  Future<AppConfig> import(String path, {bool allowEmpty = false}) async {
    final cfg = await loadFrom(path);
    if (!allowEmpty) {
      if (cfg.repos.isEmpty) {
        throw ConfigException('该配置不含任何仓库，已取消导入以免清空现有配置');
      }
      final errors = validate(cfg);
      if (errors.isNotEmpty) {
        throw ConfigException('配置校验未通过，已取消导入：\n- ${errors.join('\n- ')}');
      }
    }
    await _withLock(() => _writeLive(cfg));
    _cache = cfg;
    AppLog.info('导入配置 ← $path（仓库 ${cfg.repos.length} 个）');
    return cfg;
  }

  /// 导出：把当前配置写到目标文件（单个合并文件），返回实际写入的路径。
  /// 路径为空、指向目录时抛 [ConfigException]；未写扩展名时补 .yaml。
  Future<String> export(String path) async {
    var target = path.trim();
    if (target.isEmpty) {
      throw ConfigException('导出路径为空，已取消导出');
    }
    if (await Directory(target).exists()) {
      throw ConfigException('导出路径是目录，请指定文件名：$target');
    }
    if (p.extension(target).isEmpty) target = '$target.yaml';
    final cfg = _cache ?? await load();
    await saveTo(cfg, target);
    AppLog.info('导出配置 → $target');
    return target;
  }

  /// 旧版单文件配置（v1–v3）拆分为 v4
  Future<void> _migrateLegacy(
      Map<String, dynamic> legacy, File original) async {
    final repos = (legacy['repos'] as List? ?? const [])
        .map((e) => RepoConfig.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final appOnly = Map<String, dynamic>.from(legacy)..remove('repos');
    final oldVersion = appOnly['configVersion'] ?? 1;
    final migrated = AppConfig.fromJson(appOnly)
        .copyWith(configVersion: currentConfigVersion, repos: repos);

    // 首次迁移时备份原文件，便于回滚
    final bak = File('$configPath.bak');
    if (!await bak.exists()) {
      try {
        await original.copy(bak.path);
        AppLog.info('旧版配置已备份 → ${bak.path}');
      } catch (_) {
        // 备份失败不阻断迁移
      }
    }
    await _writeLive(migrated);
    AppLog.info('检测到旧版配置（configVersion=$oldVersion），已转换为 '
        'v$currentConfigVersion：软件配置 ${p.basename(configPath)} + '
        '仓库配置 ${p.basename(reposPath)}');
  }

  /// 软件配置 JSON（不含 repos，强制写入当前格式版本）
  Map<String, dynamic> _appJson(AppConfig config) {
    final j = config.toJson()..remove('repos');
    j['configVersion'] = currentConfigVersion;
    return j;
  }

  /// 拆分写入两个文件（原子写入：先写临时文件再替换）
  Future<void> _writeLive(AppConfig config) async {
    await _writeFile(File(configPath), _appJson(config));
    await _writeFile(File(reposPath), {
      'configVersion': currentConfigVersion,
      'repos': config.repos.map((e) => e.toJson()).toList(),
    });
    AppLog.configure(config.loggingEnabled);
  }

  Future<void> _writeFile(File file, Map<String, dynamic> json) async {
    await file.parent.create(recursive: true);
    final out = file.path.endsWith('.json')
        ? encodeJson(json)
        : YamlWriter().write(json);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(out);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  dynamic _decode(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return decodeJson(trimmed);
    }
    return _normalize(loadYaml(trimmed));
  }

  /// 将 YamlMap/YamlList 递归转为普通 Map/List
  dynamic _normalize(dynamic v) {
    if (v is YamlMap) {
      return {for (final e in v.entries) e.key.toString(): _normalize(e.value)};
    }
    if (v is YamlList) return v.map(_normalize).toList();
    return v;
  }

  Map<String, dynamic> _asMap(Object? decoded) {
    if (decoded is! Map) {
      throw ConfigException('配置内容格式不正确（应为 YAML/JSON 对象）');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// 校验配置合法性，返回错误信息列表（空表示通过）
  List<String> validate(AppConfig config) {
    final errors = <String>[];
    for (final m in config.mirrors) {
      if (m.mode == MirrorMode.regex) {
        try {
          RegExp(m.pattern);
        } catch (e) {
          errors.add('镜像「${m.name}」正则无效: $e');
        }
      }
    }
    if (config.repos.isEmpty) {
      errors.add('至少需要配置一个仓库');
    }
    for (final r in config.repos) {
      if (r.assetRules.isEmpty) {
        errors.add('仓库 ${r.fullName} 至少需要一条资产规则');
      }
      for (final rule in r.assetRules) {
        try {
          RegExp(rule.nameRegex);
        } catch (e) {
          errors.add('仓库 ${r.fullName} 规则正则无效: $e');
        }
      }
    }
    if (config.webhook.enabled && config.webhook.url.isEmpty) {
      errors.add('Webhook 已开启但未配置 URL');
    }
    return errors;
  }
}
