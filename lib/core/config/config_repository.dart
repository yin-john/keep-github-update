/// 配置仓库：加载/保存/导入导出（YAML 或 JSON），并对正则与规则做合法性校验。
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
  AppConfig? _cache;

  static const defaultFileName = 'grku_config.yaml';

  /// 从默认路径加载；文件不存在则返回空配置
  Future<AppConfig> load() async {
    final file = File(configPath);
    if (!await file.exists()) {
      _cache = const AppConfig(
        webhook: WebhookConfig(enabled: false, url: '', events: NotificationEvent.values),
      );
      AppLog.configure(_cache!.loggingEnabled);
      return _cache!;
    }
    final content = await file.readAsString();
    final decoded = _decode(content);
    _cache = AppConfig.fromJson(decoded);
    AppLog.configure(_cache!.loggingEnabled);
    return _cache!;
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

  /// 保存到指定路径（按扩展名决定 YAML/JSON）；路径为空时抛 [ConfigException]
  Future<void> saveTo(AppConfig config, String path) {
    final target = path.trim();
    if (target.isEmpty) {
      throw ConfigException('保存路径为空，已取消写入');
    }
    final prev = _writeLocks[target] ?? Future<void>.value();
    final next = prev.then((_) => _write(config, target));
    _writeLocks[target] = next.catchError((_) {});
    return next;
  }

  Future<void> _write(AppConfig config, String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final map = config.toJson();
    final out = path.endsWith('.json') ? encodeJson(map) : YamlWriter().write(map);
    // 原子写入：先写临时文件再替换，避免读到半截内容
    final tmp = File('$path.tmp');
    await tmp.writeAsString(out);
    if (await file.exists()) await file.delete();
    await tmp.rename(path);
    AppLog.configure(config.loggingEnabled);
  }

  /// 保存到默认路径
  Future<void> save(AppConfig config) => saveTo(config, configPath);

  /// 导入：用另一份文件内容覆盖当前配置。
  ///
  /// 默认拒绝用「不含任何仓库」或校验不通过的配置覆盖，避免把现有配置清空；
  /// 确需导入空配置时传 [allowEmpty] = true。
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
    await saveTo(cfg, configPath);
    _cache = cfg;
    AppLog.info('导入配置 ← $path（仓库 ${cfg.repos.length} 个）');
    return cfg;
  }

  /// 导出：把当前配置写到目标文件，返回实际写入的路径。
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
