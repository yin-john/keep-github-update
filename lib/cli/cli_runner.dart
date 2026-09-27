/// CLI 入口：子命令 list / check / update / add / remove / config / notify / tui
library;

import 'dart:io';
import 'package:args/command_runner.dart';
import '../core/config/config_repository.dart';
import '../core/config/models.dart';
import '../core/log/app_log.dart';
import '../core/updater/update_service.dart';
import 'app_context.dart';
import '../tui/tui_app.dart';

String _progress(int received, int total) {
  if (total <= 0) return '下载中 ${(received / 1024).toStringAsFixed(0)} KB';
  final pct = (received / total * 100).clamp(0, 100).toStringAsFixed(0);
  return '[$pct%] ${(received / 1024 / 1024).toStringAsFixed(1)}/${(total / 1024 / 1024).toStringAsFixed(1)} MB';
}

class GrkuCommandRunner extends CommandRunner<void> {
  GrkuCommandRunner(String configPath)
      : super('grku', 'GitHub Release 自动下载更新工具') {
    addCommand(ListCommand(configPath));
    addCommand(CheckCommand(configPath));
    addCommand(UpdateCommand(configPath));
    addCommand(RetryCommand(configPath));
    addCommand(AddCommand(configPath));
    addCommand(RemoveCommand(configPath));
    addCommand(ConfigCommand(configPath));
    addCommand(NotifyCommand(configPath));
    addCommand(TuiCommand(configPath));
  }
}

abstract class _BaseCommand extends Command<void> {
  _BaseCommand(this.configPath);
  final String configPath;
}

class ListCommand extends _BaseCommand {
  ListCommand(super.configPath);
  @override
  final name = 'list';
  @override
  final description = '列出已配置仓库与当前版本';

  @override
  Future<void> run() async {
    final ctx = await loadContext(configPath);
    if (ctx.config.repos.isEmpty) {
      print('尚未配置仓库。使用 `grku add <owner/repo>` 添加。');
      return;
    }
    for (final r in ctx.config.repos) {
      print('• ${r.fullName}  当前: ${r.lastInstalledTag ?? "未更新"}  '
          '规则数: ${r.assetRules.length}');
    }
  }
}

class CheckCommand extends _BaseCommand {
  CheckCommand(super.configPath) {
    argParser.addOption('repo', help: '仅检测指定仓库 owner/repo');
  }
  @override
  final name = 'check';
  @override
  final description = '检测可更新项';

  @override
  Future<void> run() async {
    final ctx = await loadContext(configPath);
    final repos = _filter(ctx, argResults!['repo'] as String?);
    final checks = await ctx.service.checkAll(repos);
    for (final c in checks) {
      if (c.hasUpdate) {
        print('↑ ${c.repo.fullName}: ${c.repo.lastInstalledTag ?? "无"} → ${c.release.tagName}');
      } else {
        print('= ${c.repo.fullName}: 已是最新 (${c.repo.lastInstalledTag ?? "无"})');
      }
    }
  }
}

class UpdateCommand extends _BaseCommand {
  UpdateCommand(super.configPath) {
    argParser
      ..addOption('repo', help: '仅更新指定仓库 owner/repo')
      ..addFlag('yes', abbr: 'y', help: '跳过确认', negatable: false)
      ..addFlag('dry-run', help: '仅下载不应用', negatable: false);
  }
  @override
  final name = 'update';
  @override
  final description = '下载并应用更新';

  @override
  Future<void> run() async {
    final ctx = await loadContext(configPath);
    final yes = argResults!['yes'] as bool;
    final dry = argResults!['dry-run'] as bool;
    final repos = _filter(ctx, argResults!['repo'] as String?);
    final checks = (await ctx.service.checkAll(repos))
        .where((c) => c.hasUpdate)
        .toList();
    if (checks.isEmpty) {
      print('没有需要更新的仓库。');
      return;
    }
    for (final c in checks) {
      if (!yes && !dry) {
        stdout.write('更新 ${c.repo.fullName} 到 ${c.release.tagName}? [y/N] ');
        final ans = stdin.readLineSync()?.trim().toLowerCase();
        if (ans != 'y' && ans != 'yes') {
          print('跳过 ${c.repo.fullName}');
          continue;
        }
      }
      print('更新 ${c.repo.fullName} → ${c.release.tagName}');
      final file = await ctx.service.update(
        c,
        onProgress: (r, t) => stdout.write('\r  ${_progress(r, t)}'),
        dryRun: dry,
      );
      if (dry) {
        print('\n(仅下载) 文件: ${file.path}');
      } else {
        print('\n完成: ${c.repo.fullName}');
        final updated = ctx.config.repos
            .map((e) => e.fullName == c.repo.fullName
                ? e.copyWith(lastInstalledTag: c.release.tagName)
                : e)
            .toList();
        await ctx.configRepo.save(ctx.config.copyWith(repos: updated));
      }
    }
  }
}

class RetryCommand extends _BaseCommand {
  RetryCommand(super.configPath) {
    argParser.addOption('repo', help: '指定仓库 owner/repo（留空则处理所有仓库）');
  }
  @override
  final name = 'retry';
  @override
  final description = '仅重试安装：复用已下载的文件，不重新下载';

  @override
  Future<void> run() async {
    final ctx = await loadContext(configPath);
    final repos = _filter(ctx, argResults!['repo'] as String?);
    for (final r in repos) {
      final file = await ctx.service
          .lastDownloadedFile(r, downloadDir: ctx.config.downloadDir);
      if (file == null) {
        print('- ${r.fullName}: 没有已下载的文件，请先执行 update');
        continue;
      }
      try {
        final c = await ctx.service.check(r);
        await ctx.service.applyDownloaded(c, file);
        print('✓ ${r.fullName}: 安装成功 → ${c.release.tagName}');
      } on InstallFailedException catch (e) {
        print('✗ ${r.fullName}: ${e.message}');
      } catch (e) {
        print('✗ ${r.fullName}: $e');
      }
    }
  }
}

class AddCommand extends _BaseCommand {
  AddCommand(super.configPath) {
    argParser
      ..addOption('platform',
          abbr: 'p', help: '平台', defaultsTo: PlatformType.windows.name)
      ..addOption('strategy',
          abbr: 's', help: '更新策略', defaultsTo: UpdateStrategy.portable.name)
      ..addOption('regex', abbr: 'e', help: '文件名匹配正则（必填）')
      ..addOption('install-dir', help: 'portable 安装目录')
      ..addOption('tag-filter', help: '仅匹配包含该字符串的 tag')
      ..addFlag('verify-checksum',
          help: '下载后对照 release 下的校验文件验证完整性', negatable: false)
      ..addOption('checksum-type',
          help: '校验算法', defaultsTo: ChecksumType.sha256.name)
      ..addOption('checksum-regex', help: '自定义校验文件名正则（可选）')
      ..addOption('arch',
          help: '目标架构', defaultsTo: TargetArch.any.name)
      ..addOption('install-method',
          help: 'APK 安装授权方式（root/shizuku）',
          defaultsTo: InstallMethod.root.name);
  }
  @override
  final name = 'add';
  @override
  final description = '添加仓库: grku add <owner/repo>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      print('请提供 owner/repo');
      return;
    }
    final parts = rest.first.split('/');
    if (parts.length != 2) {
      print('格式错误，应为 owner/repo');
      return;
    }
    final regex = argResults!['regex'] as String?;
    if (regex == null || regex.isEmpty) {
      print('必须通过 --regex 指定文件名匹配正则');
      return;
    }
    final platform =
        _enum(PlatformType.values, argResults!['platform'] as String, 'platform');
    if (platform == null) return;
    // 策略按平台校验：未显式指定时默认取该平台首个合法策略
    final UpdateStrategy strategy;
    if (argResults!.wasParsed('strategy')) {
      final s =
          _enum(platform.strategies, argResults!['strategy'] as String, 'strategy');
      if (s == null) {
        print('平台 ${platform.name} 仅支持策略: '
            '${platform.strategies.map((e) => e.name).join(', ')}');
        return;
      }
      strategy = s;
    } else {
      strategy = platform.strategies.first;
    }
    final checksumType = _enum(
        ChecksumType.values, argResults!['checksum-type'] as String, 'checksum-type');
    if (checksumType == null) return;
    final arch = _enum(
        TargetArch.values, argResults!['arch'] as String, 'arch');
    final installMethod = _enum(
        InstallMethod.values, argResults!['install-method'] as String, 'install-method');
    if (arch == null || installMethod == null) return;
    final ctx = await loadContext(configPath);
    final rule = AssetRule(
      platform: platform,
      strategy: strategy,
      nameRegex: regex,
      verifyChecksum: argResults!['verify-checksum'] as bool,
      checksumType: checksumType,
      checksumRegex: argResults!['checksum-regex'] as String?,
      arch: platform.usesApkInstallMethod ? arch : TargetArch.any,
    );
    final repo = RepoConfig(
      id: rest.first,
      owner: parts[0],
      repo: parts[1],
      tagFilter: argResults!['tag-filter'] as String?,
      assetRules: [rule],
      apkInstallMethod: platform.usesApkInstallMethod ? installMethod : null,
      installDir: argResults!['install-dir'] as String?,
    );
    final repos = [...ctx.config.repos, repo];
    await ctx.configRepo.save(ctx.config.copyWith(repos: repos));
    AppLog.info('添加仓库 ${repo.fullName}（规则 ${repo.assetRules.length} 条）');
    print('已添加 ${repo.fullName}');
  }
}

class RemoveCommand extends _BaseCommand {
  RemoveCommand(super.configPath);
  @override
  final name = 'remove';
  @override
  final description = '移除仓库: grku remove <owner/repo>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      print('请提供 owner/repo');
      return;
    }
    final ctx = await loadContext(configPath);
    final target = rest.first;
    final repos = ctx.config.repos.where((r) => r.fullName != target).toList();
    if (repos.length == ctx.config.repos.length) {
      print('未找到 $target');
      return;
    }
    await ctx.configRepo.save(ctx.config.copyWith(repos: repos));
    AppLog.info('移除仓库 $target');
    print('已移除 $target');
  }
}

class ConfigCommand extends _BaseCommand {
  ConfigCommand(super.configPath) {
    addSubcommand(_ImportCommand(configPath));
    addSubcommand(_ExportCommand(configPath));
    addSubcommand(_SetCommand(configPath));
  }
  @override
  final name = 'config';
  @override
  final description = '配置导入/导出/设置';
}

class _ImportCommand extends _BaseCommand {
  _ImportCommand(super.configPath);
  @override
  final name = 'import';
  @override
  final description = '从文件导入配置';
  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    final file = rest.isEmpty ? null : rest.first.trim();
    if (file == null || file.isEmpty) return print('请提供文件路径');
    final ctx = await loadContext(configPath);
    try {
      final cfg = await ctx.configRepo.import(file);
      print('已导入配置，仓库数: ${cfg.repos.length}');
    } on ConfigException catch (e) {
      print('导入失败：$e');
    } catch (e) {
      print('导入失败：$e');
    }
  }
}

class _ExportCommand extends _BaseCommand {
  _ExportCommand(super.configPath);
  @override
  final name = 'export';
  @override
  final description = '导出配置到文件';
  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    final file = rest.isEmpty ? null : rest.first.trim();
    if (file == null || file.isEmpty) return print('请提供文件路径');
    final ctx = await loadContext(configPath);
    try {
      final written = await ctx.configRepo.export(file);
      print('已导出到 $written');
    } on ConfigException catch (e) {
      print('导出失败：$e');
    } catch (e) {
      print('导出失败：$e');
    }
  }
}

class _SetCommand extends _BaseCommand {
  _SetCommand(super.configPath);
  @override
  final name = 'set';
  @override
  final description = '设置配置项: set <key> <value>';
  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) return print('用法: grku config set <key> <value>');
    final key = rest[0];
    final value = rest[1];
    final ctx = await loadContext(configPath);
    final c = ctx.config;
    switch (key) {
      case 'githubToken':
        await ctx.configRepo.save(c.copyWith(githubToken: value));
      case 'systemNotificationsEnabled':
        await ctx.configRepo
            .save(c.copyWith(systemNotificationsEnabled: value == 'true'));
      case 'downloadDir':
        await ctx.configRepo.save(c.copyWith(downloadDir: value));
      case 'webhook.enabled':
        await ctx.configRepo.save(c.copyWith(
            webhook: c.webhook.copyWith(enabled: value == 'true')));
      case 'webhook.url':
        await ctx.configRepo
            .save(c.copyWith(webhook: c.webhook.copyWith(url: value)));
      default:
        print('未知配置项: $key');
        return;
    }
    print('已更新 $key');
  }
}

class NotifyCommand extends _BaseCommand {
  NotifyCommand(super.configPath) {
    argParser.addOption('title', abbr: 't', defaultsTo: 'grku 测试');
  }
  @override
  final name = 'notify';
  @override
  final description = '发送测试系统通知';
  @override
  Future<void> run() async {
    final restMsg = argResults!.rest;
    final msg = restMsg.isEmpty ? '这是一条测试通知' : restMsg.join(' ');
    final ctx = await loadContext(configPath);
    await ctx.service.notifications?.dispatch(
      NotificationEvent.updateSuccess,
      const RepoConfig(id: 'test', owner: 'test', repo: 'test', assetRules: []),
      'test',
      ctx.service.currentPlatform,
      message: msg,
    );
    print('已尝试发送通知');
  }
}

class TuiCommand extends _BaseCommand {
  TuiCommand(super.configPath);
  @override
  final name = 'tui';
  @override
  final description = '启动终端交互界面 (TUI)';
  @override
  Future<void> run() async => runTui(configPath);
}

T? _enum<T extends Enum>(List<T> values, String s, String what) {
  final found = values.where((e) => e.name == s).toList();
  if (found.isEmpty) {
    print('无效的$what: $s；可选: ${values.map((e) => e.name).join(', ')}');
    return null;
  }
  return found.first;
}

List<RepoConfig> _filter(AppContext ctx, String? repo) {
  if (repo == null) return ctx.config.repos;
  return ctx.config.repos.where((r) => r.fullName == repo).toList();
}
