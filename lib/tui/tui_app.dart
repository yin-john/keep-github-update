/// TUI 终端交互界面（dart_console2）
/// 功能：仓库列表 / 检测 / 更新 / 全部更新 / 添加 / 删除 / 详情编辑 / 全局配置
library;

import 'package:dart_console2/dart_console2.dart';
import '../core/config/models.dart';
import '../cli/app_context.dart';
import '../core/updater/update_service.dart';
import 'tui_widgets.dart';

Future<void> runTui(String configPath) async {
  var ctx = await loadContext(configPath);
  final console = Console();
  console.hideCursor();
  try {
    ctx = await _mainScreen(console, ctx, configPath);
  } finally {
    console.showCursor();
    console.resetColorAttributes();
    console.clearScreen();
    console.writeLine('再见。');
  }
}

// ---------------- 通用控件 ----------------

/// 单行文本输入；optional=true 时 Esc 仅跳过（返回空串），否则 Esc 取消（返回 null）
Future<String?> _prompt(Console c, String label, {bool optional = false}) async {
  c.resetColorAttributes();
  c.write(label);
  return c.readLine(cancelOnEscape: !optional, cancelOnEOF: false);
}

Future<bool> _confirm(Console c, String text) async {
  c.resetColorAttributes();
  c.write('$text [y/N] ');
  final v = c.readLine(cancelOnEscape: true)?.trim().toLowerCase();
  return v == 'y' || v == 'yes';
}

void _pause(Console c, String text) {
  c.resetColorAttributes();
  c.writeLine(text);
  c.writeLine('按任意键继续。');
  c.readKey();
}

Future<int?> _choose<T>(Console c, String title, List<T> options, int initial) async {
  var idx = initial.clamp(0, options.length - 1);
  while (true) {
    c.clearScreen();
    c.setForegroundColor(ConsoleColor.cyan);
    c.setTextStyle(bold: true);
    c.writeLine(title);
    c.resetColorAttributes();
    c.writeLine('');
    for (var i = 0; i < options.length; i++) {
      final mark = i == idx ? '▶ ' : '  ';
      if (i == idx) c.setForegroundColor(ConsoleColor.brightGreen);
      c.writeLine('$mark${i + 1}. ${options[i]}');
      if (i == idx) c.resetColorAttributes();
    }
    c.writeLine('');
    c.writeLine('↑/↓ 或数字键选择 · Enter 确认 · Esc 取消');
    final k = c.readKey();
    if (k.controlChar == ControlCharacter.arrowDown) {
      idx = (idx + 1) % options.length;
    } else if (k.controlChar == ControlCharacter.arrowUp) {
      idx = (idx - 1 + options.length) % options.length;
    } else if (k.controlChar == ControlCharacter.enter) {
      return idx;
    } else if (k.controlChar == ControlCharacter.escape) {
      return null;
    } else if (!k.isControl &&
        k.char.compareTo('1') >= 0 &&
        k.char.compareTo('9') <= 0) {
      final n = int.parse(k.char) - 1;
      if (n < options.length) return n;
    }
  }
}

// ---------------- 主界面 ----------------

Future<AppContext> _mainScreen(
    Console c, AppContext ctx, String configPath) async {
  var selected = 0;
  var msg =
      '↑/↓ 选择 · Enter 检测 · U 更新 · 空格 全部更新 · A 添加 · R 删除 · V 详情 · C 配置 · Q 退出';
  final hasUpdate = <int, bool>{};

  void render() {
    if (ctx.config.repos.isNotEmpty && selected >= ctx.config.repos.length) {
      selected = 0;
    }
    c.clearScreen();
    c.setForegroundColor(ConsoleColor.cyan);
    c.setTextStyle(bold: true);
    c.writeLine('==== GRKU 终端更新工具 ====');
    c.resetColorAttributes();
    c.writeLine(
        '仓库: ${ctx.config.repos.length}  ·  全局通知: ${ctx.config.systemNotificationsEnabled ? '开' : '关'}  ·  下载目录: ${ctx.config.downloadDir ?? '(默认临时)'}');
    c.writeLine(
        '当前平台: ${ctx.service.currentPlatform.name}  ·  APK 默认授权: ${ctx.config.defaultApkInstallMethod.label}');
    c.writeLine('');
    if (ctx.config.repos.isEmpty) {
      c.writeLine('（暂无仓库，按 A 添加）');
    } else {
      for (var i = 0; i < ctx.config.repos.length; i++) {
        final r = ctx.config.repos[i];
        final mark = i == selected ? '▶ ' : '  ';
        if (i == selected) c.setForegroundColor(ConsoleColor.brightGreen);
        final upd = hasUpdate[i] == true ? '  ↑可更新' : '';
        c.writeLine(
            '$mark${r.fullName.padRight(30)} [${r.lastInstalledTag ?? '未更新'}]$upd');
        if (i == selected) c.resetColorAttributes();
      }
    }
    c.writeLine('');
    c.writeLine('────────────────────────────────────────');
    c.setForegroundColor(ConsoleColor.yellow);
    c.writeLine(msg);
    c.resetColorAttributes();
  }

  while (true) {
    render();
    final k = c.readKey();
    if (k.controlChar == ControlCharacter.escape || k.char == 'q' || k.char == 'Q') {
      break;
    } else if (k.controlChar == ControlCharacter.arrowDown) {
      if (ctx.config.repos.isNotEmpty) {
        selected = (selected + 1) % ctx.config.repos.length;
      }
    } else if (k.controlChar == ControlCharacter.arrowUp) {
      if (ctx.config.repos.isNotEmpty) {
        selected = (selected - 1 + ctx.config.repos.length) % ctx.config.repos.length;
      }
    } else if (k.controlChar == ControlCharacter.enter) {
      if (ctx.config.repos.isEmpty) continue;
      final r = ctx.config.repos[selected];
      msg = '检测中: ${r.fullName} …';
      render();
      try {
        final chk = await ctx.service.check(r);
        hasUpdate[selected] = chk.hasUpdate;
        msg = chk.hasUpdate
            ? '${r.fullName}: 可更新 → ${chk.release.tagName}（按 U 更新）'
            : '${r.fullName}: 已是最新 (${r.lastInstalledTag ?? "无"})';
      } catch (e) {
        msg = '检测失败: $e';
      }
    } else if (k.char == 'u' || k.char == 'U') {
      if (ctx.config.repos.isEmpty) continue;
      final r = ctx.config.repos[selected];
      msg = '检测中: ${r.fullName} …';
      render();
      UpdateCheck chk;
      try {
        chk = await ctx.service.check(r);
      } catch (e) {
        msg = '检测失败: $e';
        continue;
      }
      hasUpdate[selected] = chk.hasUpdate;
      if (!chk.hasUpdate) {
        msg = '${r.fullName}: 无需更新';
        continue;
      }
      if (!await _confirm(c, '更新 ${r.fullName} 到 ${chk.release.tagName}?')) {
        msg = '已取消';
        continue;
      }
      ctx = await _doUpdate(c, ctx, r, chk, configPath);
      hasUpdate[selected] = false;
      msg = '${r.fullName}: 更新完成 → ${chk.release.tagName}';
    } else if (k.char == ' ' || k.char == 'b' || k.char == 'B') {
      ctx = await _updateAll(c, ctx, configPath);
      hasUpdate.clear();
      msg = '已处理全部仓库';
    } else if (k.char == 'a' || k.char == 'A') {
      ctx = await _addScreen(c, ctx, configPath);
      selected = 0;
      hasUpdate.clear();
      msg = '已刷新仓库列表';
    } else if (k.char == 'r' || k.char == 'R') {
      ctx = await _removeScreen(c, ctx, configPath);
      selected = 0;
      hasUpdate.clear();
      msg = '已刷新仓库列表';
    } else if (k.char == 'v' || k.char == 'V') {
      if (ctx.config.repos.isEmpty) continue;
      ctx = await _detailScreen(c, ctx, configPath, selected);
      msg = '已刷新';
    } else if (k.char == 'c' || k.char == 'C') {
      ctx = await _configScreen(c, ctx, configPath);
      msg = '已保存全局配置';
    }
  }
  return ctx;
}

// ---------------- 更新执行 ----------------

Future<AppContext> _doUpdate(Console c, AppContext ctx, RepoConfig repo,
    UpdateCheck chk, String configPath) async {
  c.clearScreen();
  c.writeLine('更新 ${repo.fullName} → ${chk.release.tagName}');
  try {
    await ctx.service.update(chk, onProgress: (rc, t) {
      c.writeLine('  ${formatProgress(rc, t)} ${progressBar(t > 0 ? rc / t : 0)}');
    });
    final updated = ctx.config.repos
        .map((e) => e.fullName == repo.fullName
            ? e.copyWith(lastInstalledTag: chk.release.tagName)
            : e)
        .toList();
    await ctx.configRepo.save(ctx.config.copyWith(repos: updated));
    c.writeLine('完成: ${repo.fullName} → ${chk.release.tagName}');
  } catch (e) {
    c.writeLine('失败: $e');
  }
  _pause(c, '');
  return loadContext(configPath);
}

Future<AppContext> _updateAll(
    Console c, AppContext ctx, String configPath) async {
  c.clearScreen();
  c.writeLine('批量检测中 …');
  final checks = await ctx.service.checkAll(ctx.config.repos);
  final updatable = checks.where((x) => x.hasUpdate).toList();
  if (updatable.isEmpty) {
    _pause(c, '没有可更新的仓库。');
    return ctx;
  }
  var cur = ctx;
  for (final chk in updatable) {
    c.writeLine('更新 ${chk.repo.fullName} → ${chk.release.tagName}');
    try {
      await cur.service.update(chk, onProgress: (rc, t) {
        c.writeLine('  ${formatProgress(rc, t)} ${progressBar(t > 0 ? rc / t : 0)}');
      });
      final updated = cur.config.repos
          .map((e) => e.fullName == chk.repo.fullName
              ? e.copyWith(lastInstalledTag: chk.release.tagName)
              : e)
          .toList();
      await cur.configRepo.save(cur.config.copyWith(repos: updated));
      cur = await loadContext(configPath);
      c.writeLine('  完成: ${chk.repo.fullName}');
    } catch (e) {
      c.writeLine('  失败: $e');
    }
  }
  _pause(c, '批量更新结束。');
  return cur;
}

// ---------------- 添加仓库 ----------------

Future<AppContext> _addScreen(
    Console c, AppContext ctx, String configPath) async {
  c.clearScreen();
  c.setForegroundColor(ConsoleColor.cyan);
  c.setTextStyle(bold: true);
  c.writeLine('添加仓库');
  c.resetColorAttributes();
  c.writeLine('');

  final input = await _prompt(c, '仓库 (owner/repo): ');
  if (input == null || input.isEmpty) {
    _pause(c, '已取消');
    return ctx;
  }
  final parts = input.split('/');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    _pause(c, '格式错误，应为 owner/repo');
    return ctx;
  }
  final owner = parts[0];
  final repo = parts[1];

  final pIdx = await _choose(c, '选择平台',
      PlatformType.values.map((e) => e.name).toList(), PlatformType.windows.index);
  if (pIdx == null) {
    _pause(c, '已取消');
    return ctx;
  }
  final platform = PlatformType.values[pIdx];

  final platformStrategies = platform.strategies;
  final sIdx = await _choose(c, '选择更新策略',
      platformStrategies.map((e) => e.label).toList(), 0);
  if (sIdx == null) {
    _pause(c, '已取消');
    return ctx;
  }
  final strategy = platformStrategies[sIdx];

  final regex = await _prompt(c, '文件名匹配正则 (如 .*windows.*\\.zip): ');
  if (regex == null || regex.isEmpty) {
    _pause(c, '正则不能为空');
    return ctx;
  }

  final verify =
      await _confirm(c, '是否下载后校验完整性（对照 release 下校验文件）?');
  var checksumType = ChecksumType.sha256;
  if (verify) {
    final ct = await _choose(c, '校验算法',
        ChecksumType.values.map((e) => e.name).toList(), 0);
    if (ct == null) {
      _pause(c, '已取消');
      return ctx;
    }
    checksumType = ChecksumType.values[ct];
  }

  var arch = TargetArch.any;
  if (platform == PlatformType.android) {
    final ai = await _choose(c, '目标架构',
        TargetArch.values.map((e) => e.label).toList(), 0);
    if (ai == null) {
      _pause(c, '已取消');
      return ctx;
    }
    arch = TargetArch.values[ai];
  }

  String? installDir;
  String? containerName;
  String? dockerRunArgs;
  InstallMethod? apkMethod;
  if (strategy == UpdateStrategy.portable || strategy == UpdateStrategy.installer) {
    installDir = await _prompt(c, '安装目录 (可留空): ', optional: true);
    if (installDir != null && installDir.isEmpty) installDir = null;
  } else if (strategy == UpdateStrategy.docker) {
    containerName = await _prompt(c, '容器名: ', optional: true);
    if (containerName != null && containerName.isEmpty) containerName = null;
    dockerRunArgs = await _prompt(c, 'docker run 额外参数 (可留空): ', optional: true);
    if (dockerRunArgs != null && dockerRunArgs.isEmpty) dockerRunArgs = null;
  } else if (strategy == UpdateStrategy.module ||
      strategy == UpdateStrategy.apk) {
    final mi = await _choose(c, '安装授权方式',
        InstallMethod.values.map((e) => e.label).toList(), 0);
    if (mi == null) {
      _pause(c, '已取消');
      return ctx;
    }
    apkMethod = InstallMethod.values[mi];
  }

  final tf = await _prompt(c, 'tag 过滤关键字 (可留空): ', optional: true);
  final tagFilter = (tf != null && tf.isNotEmpty) ? tf : null;

  final rule = AssetRule(
    platform: platform,
    strategy: strategy,
    nameRegex: regex,
    verifyChecksum: verify,
    checksumType: checksumType,
    arch: arch,
  );
  final repoCfg = RepoConfig(
    id: '$owner/$repo',
    owner: owner,
    repo: repo,
    tagFilter: tagFilter,
    assetRules: [rule],
    installDir: installDir,
    containerName: containerName,
    dockerRunArgs: dockerRunArgs,
    apkInstallMethod: apkMethod,
  );
  final newRepos = [...ctx.config.repos, repoCfg];
  await ctx.configRepo.save(ctx.config.copyWith(repos: newRepos));
  _pause(c, '已添加 $owner/$repo');
  return loadContext(configPath);
}

// ---------------- 删除仓库 ----------------

Future<AppContext> _removeScreen(
    Console c, AppContext ctx, String configPath) async {
  var cur = ctx;
  while (true) {
    if (cur.config.repos.isEmpty) {
      _pause(c, '暂无仓库');
      return cur;
    }
    final idx = await _choose(c, '选择要删除的仓库 (Esc 返回)',
        cur.config.repos.map((r) => r.fullName).toList(), 0);
    if (idx == null) return cur;
    final r = cur.config.repos[idx];
    if (await _confirm(c, '确认删除 ${r.fullName}?')) {
      final newRepos = [...cur.config.repos]..removeAt(idx);
      await cur.configRepo.save(cur.config.copyWith(repos: newRepos));
      cur = await loadContext(configPath);
      c.writeLine('已删除 ${r.fullName}');
    }
  }
}

// ---------------- 仓库详情 / 编辑 ----------------

Future<AppContext> _detailScreen(
    Console c, AppContext ctx, String configPath, int index) async {
  var cur = ctx;
  var i = index;
  while (true) {
    if (cur.config.repos.isEmpty) return cur;
    if (i >= cur.config.repos.length) i = 0;
    final r = cur.config.repos[i];
    c.clearScreen();
    c.setForegroundColor(ConsoleColor.cyan);
    c.setTextStyle(bold: true);
    c.writeLine('仓库详情: ${r.fullName}');
    c.resetColorAttributes();
    c.writeLine('');
    c.writeLine('当前版本   : ${r.lastInstalledTag ?? '未更新'}');
    c.writeLine('tag 过滤   : ${r.tagFilter ?? '(无)'}');
    c.writeLine('通知       : ${r.notificationsEnabled ? '开' : '关'}');
    c.writeLine('安装目录   : ${r.installDir ?? '(默认)'}');
    if (r.containerName != null) c.writeLine('容器名     : ${r.containerName}');
    if (r.dockerRunArgs != null) {
      c.writeLine('docker 参数: ${r.dockerRunArgs}');
    }
    if (r.apkInstallMethod != null) {
      c.writeLine('APK 授权   : ${r.apkInstallMethod!.label}');
    }
    c.writeLine('资产规则数 : ${r.assetRules.length}');
    for (var k = 0; k < r.assetRules.length; k++) {
      final rule = r.assetRules[k];
      c.writeLine(
          '  ${k + 1}. [${rule.platform.name}/${rule.strategy.label}] ${rule.nameRegex}'
          ' 校验:${rule.verifyChecksum ? rule.checksumType.name : '关'}'
          '${rule.arch != TargetArch.any ? ' 架构:${rule.arch.label}' : ''}');
    }
    c.writeLine('');
    c.writeLine('E 编辑安装信息 · N 通知开关 · T tag 过滤 · D 删除 · ←/→ 切换仓库 · Esc 返回');
    final k = c.readKey();
    if (k.controlChar == ControlCharacter.escape) {
      return cur;
    } else if (k.controlChar == ControlCharacter.arrowRight) {
      i = (i + 1) % cur.config.repos.length;
    } else if (k.controlChar == ControlCharacter.arrowLeft) {
      i = (i - 1 + cur.config.repos.length) % cur.config.repos.length;
    } else if (k.char == 'd' || k.char == 'D') {
      if (await _confirm(c, '确认删除 ${r.fullName}?')) {
        final newRepos = [...cur.config.repos]..removeAt(i);
        await cur.configRepo.save(cur.config.copyWith(repos: newRepos));
        cur = await loadContext(configPath);
        if (cur.config.repos.isEmpty) return cur;
      }
    } else if (k.char == 'n' || k.char == 'N') {
      final newRepos = cur.config.repos
          .map((e) => e.fullName == r.fullName
              ? e.copyWith(notificationsEnabled: !e.notificationsEnabled)
              : e)
          .toList();
      await cur.configRepo.save(cur.config.copyWith(repos: newRepos));
      cur = await loadContext(configPath);
    } else if (k.char == 't' || k.char == 'T') {
      final tf = await _prompt(c, 'tag 过滤关键字 (留空=无): ', optional: true);
      final newRepos = cur.config.repos
          .map((e) => e.fullName == r.fullName
              ? e.copyWith(tagFilter: (tf != null && tf.isNotEmpty) ? tf : null)
              : e)
          .toList();
      await cur.configRepo.save(cur.config.copyWith(repos: newRepos));
      cur = await loadContext(configPath);
    } else if (k.char == 'e' || k.char == 'E') {
      final strat = r.assetRules.isNotEmpty
          ? r.assetRules.first.strategy
          : UpdateStrategy.portable;
      if (strat == UpdateStrategy.portable || strat == UpdateStrategy.installer) {
        final v = await _prompt(c, '安装目录 (留空=默认): ', optional: true);
        final newRepos = cur.config.repos
            .map((e) => e.fullName == r.fullName
                ? e.copyWith(
                    installDir: (v != null && v.isNotEmpty) ? v : null)
                : e)
            .toList();
        await cur.configRepo.save(cur.config.copyWith(repos: newRepos));
        cur = await loadContext(configPath);
      } else if (strat == UpdateStrategy.docker) {
        final cn = await _prompt(c, '容器名: ', optional: true);
        final dr = await _prompt(c, 'docker run 参数 (可留空): ', optional: true);
        final newRepos = cur.config.repos
            .map((e) => e.fullName == r.fullName
                ? e.copyWith(
                    containerName: (cn != null && cn.isNotEmpty) ? cn : null,
                    dockerRunArgs: (dr != null && dr.isNotEmpty) ? dr : null,
                  )
                : e)
            .toList();
        await cur.configRepo.save(cur.config.copyWith(repos: newRepos));
        cur = await loadContext(configPath);
      } else if (strat == UpdateStrategy.module || strat == UpdateStrategy.apk) {
        final mi = await _choose(c, 'APK/模块 安装授权方式',
            InstallMethod.values.map((e) => e.label).toList(), 0);
        if (mi != null) {
          final newRepos = cur.config.repos
              .map((e) => e.fullName == r.fullName
                  ? e.copyWith(apkInstallMethod: InstallMethod.values[mi])
                  : e)
              .toList();
          await cur.configRepo.save(cur.config.copyWith(repos: newRepos));
          cur = await loadContext(configPath);
        }
      }
    }
  }
}

// ---------------- 全局配置 ----------------

Future<AppContext> _configScreen(
    Console c, AppContext ctx, String configPath) async {
  var cur = ctx;
  while (true) {
    c.clearScreen();
    c.setForegroundColor(ConsoleColor.cyan);
    c.setTextStyle(bold: true);
    c.writeLine('全局配置');
    c.resetColorAttributes();
    c.writeLine('');
    c.writeLine(
        'GitHub Token : ${cur.config.githubToken != null ? '已设置(${cur.config.githubToken!.length}字符)' : '(未设置)'}');
    c.writeLine(
        '系统通知     : ${cur.config.systemNotificationsEnabled ? '开' : '关'}');
    c.writeLine('下载目录     : ${cur.config.downloadDir ?? '(默认临时)'}');
    c.writeLine('APK 默认授权 : ${cur.config.defaultApkInstallMethod.label}');
    c.writeLine('镜像数量     : ${cur.config.mirrors.length}');
    c.writeLine(
        'Webhook      : ${cur.config.webhook.enabled ? '开 (${cur.config.webhook.url})' : '关'}');
    c.writeLine('');
    c.writeLine('T Token · N 通知 · D 下载目录 · M APK授权 · W Webhook开关 · U Webhook URL · Esc 返回');
    final k = c.readKey();
    if (k.controlChar == ControlCharacter.escape) {
      return cur;
    } else if (k.char == 't' || k.char == 'T') {
      final v = await _prompt(c, 'GitHub Token (留空=清除): ', optional: true);
      await cur.configRepo.save(cur.config.copyWith(
          githubToken: (v != null && v.isNotEmpty) ? v : null));
      cur = await loadContext(configPath);
    } else if (k.char == 'n' || k.char == 'N') {
      await cur.configRepo.save(cur.config
          .copyWith(systemNotificationsEnabled: !cur.config.systemNotificationsEnabled));
      cur = await loadContext(configPath);
    } else if (k.char == 'd' || k.char == 'D') {
      final v = await _prompt(c, '下载目录 (留空=默认): ', optional: true);
      await cur.configRepo.save(cur.config.copyWith(
          downloadDir: (v != null && v.isNotEmpty) ? v : null));
      cur = await loadContext(configPath);
    } else if (k.char == 'm' || k.char == 'M') {
      final mi = await _choose(c, 'APK 默认授权方式',
          InstallMethod.values.map((e) => e.label).toList(), 0);
      if (mi != null) {
        await cur.configRepo
            .save(cur.config.copyWith(defaultApkInstallMethod: InstallMethod.values[mi]));
        cur = await loadContext(configPath);
      }
    } else if (k.char == 'w' || k.char == 'W') {
      await cur.configRepo.save(cur.config.copyWith(
          webhook: cur.config.webhook.copyWith(enabled: !cur.config.webhook.enabled)));
      cur = await loadContext(configPath);
    } else if (k.char == 'u' || k.char == 'U') {
      final v = await _prompt(c, 'Webhook URL (留空=清除): ', optional: true);
      await cur.configRepo.save(cur.config.copyWith(
          webhook: cur.config.webhook
              .copyWith(url: (v != null && v.isNotEmpty) ? v : null)));
      cur = await loadContext(configPath);
    }
  }
}
