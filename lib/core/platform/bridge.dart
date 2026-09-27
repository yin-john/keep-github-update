/// 平台桥接：通过进程调用完成各端专属操作（解压/安装/刷模块/docker/系统通知）。
/// 采用 dart:io Process，GUI 与 CLI/TUI 共用同一套实现，无需 MethodChannel。
library;

import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../config/app_paths.dart';
import '../config/models.dart';
import '../log/app_log.dart';
import '../version/installed_version.dart';
import 'module_console.dart';

/// 判断下载文件是否为需解压的压缩包（单文件便携版如 .exe / .AppImage 返回 false）
bool isArchiveFile(String path) {
  final lower = path.toLowerCase();
  const exts = [
    '.zip',
    '.7z',
    '.rar',
    '.tar',
    '.tar.gz',
    '.tgz',
    '.tar.xz',
    '.txz',
    '.tar.bz2',
    '.tbz2',
    '.tar.zst',
  ];
  return exts.any(lower.endsWith);
}

abstract class PlatformBridge {
  /// 解压 zip 到目标目录（portable）。
  /// [preserve] 中的路径正则若匹配到安装目录内的条目，则在覆盖前保留（不删除），
  /// 用于保护数据/配置目录。
  Future<void> extractZip(String zipPath, String targetDir,
      {List<String> preserve});

  /// Windows/Linux：把单个可执行文件（portable exe / AppImage / 单文件二进制）
  /// 放入安装目录，保留原文件名（同名覆盖）；非 Windows 平台补可执行权限。
  Future<void> placePortableFile(String path, String targetDir);

  /// Windows：静默安装 msi，[extraArgs] 为追加参数
  Future<void> installMsi(String path, {String? extraArgs});

  /// Windows：静默运行 setup.exe（默认 /S）
  Future<void> runSetup(String path, {String args = '/S'});

  /// Android：按授权方式静默安装/更新 APK（保留数据覆盖安装）
  Future<void> installApk(String path, {required InstallMethod method});

  /// Android：卸载指定包名（root / Shizuku），用于签名不一致时的强制重装。
  /// [keepData] 为真时用 `pm uninstall -k` 保留应用数据目录（重装后仍然可用）。
  Future<void> uninstallApk(String packageName, {bool keepData});

  /// Android：检测当前设备是否可获得 root 权限
  Future<bool> isRootAvailable();

  /// Android：检测 Shizuku 命令行是否可用（已授权）
  Future<bool> isShizukuAvailable();

  /// 当前设备的目标架构（仅 Android 有实际意义，其余返回 any）
  Future<TargetArch> deviceArch();

  /// Android：root 刷入 Magisk/KernelSU 模块。
  /// 安装器输出实时推送到 [ModuleInstallConsole]（终端窗口）并写入日志。
  Future<void> flashModule(String path);

  /// Android：读取设备上已装 Magisk/KernelSU 模块的 module.prop（模块 ID → 内容）
  Future<Map<String, String>> androidModuleProps();

  /// Android：读取设备上已装应用的 versionName（包名 → 版本）
  Future<Map<String, String>> androidPackageVersions();

  /// Linux：docker 拉取镜像并按容器名重建（runArgs 提供原运行参数/卷挂载）
  Future<void> dockerUpdate(String image,
      {String? containerName, String? runArgs});

  /// 系统级通知（OS 原生，失败降级为 print）
  Future<void> notifySystem(String title, String body, NotificationLevel level);

  /// 在系统文件管理器中打开目录（Windows/Linux/macOS）
  Future<void> openFolder(String path);

  /// 用系统浏览器打开 URL（Windows/Linux；Android 走 AndroidEnv.openUrl）
  Future<void> openExternal(String url);

  /// Windows/Linux：启动便携版应用。
  /// [file] 为相对 [installDir] 的启动文件；[cmd] 非空时作为完整命令
  /// 在安装目录下执行（覆盖直接启动文件的默认行为）。
  Future<void> launchPortableApp(
      {required String installDir, required String file, String? cmd});
}

class DefaultPlatformBridge implements PlatformBridge {
  const DefaultPlatformBridge();

  @override
  Future<void> extractZip(String zipPath, String targetDir,
      {List<String> preserve = const []}) async {
    final dir = Directory(targetDir);
    if (await dir.exists()) {
      if (preserve.isEmpty) {
        await dir.delete(recursive: true);
      } else {
        // 保留匹配 preserve 正则的条目（数据/配置目录），其余删除后再解压
        final regs = <RegExp>[];
        for (final pat in preserve) {
          try {
            regs.add(RegExp(pat));
          } catch (_) {
            // 忽略非法正则
          }
        }
        await for (final e in dir.list()) {
          final rel = p.relative(e.path, from: targetDir);
          // 目录同时用「带斜杠」的路径匹配，便于写 ^data/ 这类规则
          final isDir = e is Directory;
          final keep = regs.any(
              (r) => r.hasMatch(rel) || (isDir && r.hasMatch('$rel/')));
          if (!keep) {
            try {
              await e.delete(recursive: true);
            } catch (_) {}
          }
        }
      }
    }
    await dir.create(recursive: true);
    await extractFileToDisk(zipPath, targetDir);
  }

  @override
  Future<void> placePortableFile(String path, String targetDir) async {
    final dir = Directory(targetDir);
    await dir.create(recursive: true);
    final target = p.join(targetDir, p.basename(path));
    if (p.equals(p.absolute(path), p.absolute(target))) return;
    final f = File(target);
    if (await f.exists()) {
      // 先删除再复制，规避 Windows 上被占用/只读导致的复制失败
      await f.delete();
    }
    await File(path).copy(target);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['+x', target]);
      } catch (_) {
        // 权限设置失败不阻断更新
      }
    }
    print('已放置便携文件 → $target');
  }

  @override
  Future<void> installMsi(String path, {String? extraArgs}) async {
    final extra = (extraArgs ?? '')
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty);
    await _runElevated('msiexec', ['/i', path, '/qn', '/norestart', ...extra]);
  }

  @override
  Future<void> runSetup(String path, {String args = '/S'}) async {
    final parts = args.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    await _runElevated(path, parts);
  }

  @override
  Future<void> installApk(String path, {required InstallMethod method}) async {
    if (method == InstallMethod.normal) {
      throw Exception('普通安装需通过系统安装器完成（请使用系统安装器方式）');
    }
    if (method == InstallMethod.root) {
      if (!await isRootAvailable()) {
        throw Exception('未获取到 root 权限，无法静默安装 APK');
      }
      await _installViaShell(path, const ['su', '-c'],
          '请确认已 root 且允许本应用获取 root 权限');
      return;
    }
    // Shizuku：优先使用 shizuku 命令转发；若不可用但应用已获 shell 权限，则直接 pm
    if (await isShizukuAvailable()) {
      await _installViaShell(path, const ['shizuku', '-c'],
          '请确认 Shizuku 正在运行并已授权本应用');
      return;
    }
    final r = await Process.run('pm', ['install', '-r', '-t', path]);
    if (r.exitCode != 0) {
      throw Exception('安装失败（请确认已在 Shizuku 中授权本应用）: ${r.stderr}');
    }
  }

  /// 经 root / Shizuku 静默安装。
  ///
  /// 关键：先把 APK 复制到 /data/local/tmp 再安装。
  /// system_server 读不到 /sdcard（FUSE）下的文件，直接用外部存储路径会报
  /// "System server has no access to read file context ... Can't open file"。
  Future<void> _installViaShell(
      String path, List<String> shell, String hint) async {
    final tmp = await _pushToLocalTmp(path, shell);
    try {
      final r = await Process.run(
          shell.first, [...shell.sublist(1), 'pm install -r -t "$tmp"']);
      final out = '${r.stdout}${r.stderr}';
      if (r.exitCode != 0 || !out.contains('Success')) {
        throw Exception('APK 安装失败（$hint）: $out');
      }
    } finally {
      if (tmp != path) {
        try {
          await Process.run(
              shell.first, [...shell.sublist(1), 'rm -f "$tmp"']);
        } catch (_) {
          // 清理失败不影响结果
        }
      }
    }
  }

  /// 复制 APK 到 /data/local/tmp（失败时退回原路径）
  Future<String> _pushToLocalTmp(String path, List<String> shell) async {
    final tmp = '/data/local/tmp/grku_${p.basename(path)}';
    try {
      final r = await Process.run(shell.first,
          [...shell.sublist(1), 'cp -f "$path" "$tmp" && chmod 644 "$tmp"']);
      if (r.exitCode == 0) return tmp;
    } catch (_) {
      // 忽略，使用原路径
    }
    return path;
  }

  @override
  Future<void> uninstallApk(String packageName, {bool keepData = true}) async {
    if (!Platform.isAndroid) {
      throw Exception('仅 Android 支持卸载应用');
    }
    // 安全护栏：任何情况下都不允许卸载本应用自身，
    // 否则「自己更新自己」时会把正在运行的应用直接删掉，且无法再安装回来。
    if (packageName.trim().toLowerCase() == androidPackageId.toLowerCase()) {
      throw Exception('拒绝卸载本应用自身（$packageName）');
    }
    // -k 保留 /data/data/<pkg>，重装（即使签名不同）后数据仍在
    final cmd = keepData
        ? 'pm uninstall -k --user 0 $packageName'
        : 'pm uninstall $packageName';
    const candidates = [
      ['su', '-c'],
      ['shizuku', '-c'],
    ];
    final messages = <String>[];
    for (final c in candidates) {
      try {
        final r = await Process.run(c.first, [...c.sublist(1), cmd]);
        final out = '${r.stdout}${r.stderr}'.trim();
        if (r.exitCode == 0 && out.contains('Success')) return;
        if (out.isNotEmpty) messages.add(out.split('\n').first);
      } catch (e) {
        messages.add('$e');
      }
    }
    throw Exception('卸载 $packageName 失败（需要 root 或 Shizuku 授权）'
        '${messages.isEmpty ? '' : '：${messages.first}'}');
  }

  @override
  Future<bool> isRootAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await Process.run('su', ['-c', 'echo ok']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isShizukuAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await Process.run('shizuku', ['-v']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<TargetArch> deviceArch() async {
    if (!Platform.isAndroid) return TargetArch.any;
    try {
      final r = await Process.run('getprop', ['ro.product.cpu.abi']);
      final out = (r.stdout as String? ?? '').toLowerCase();
      if (out.contains('arm64') || out.contains('aarch64')) {
        return TargetArch.arm64;
      }
      if (out.contains('arm')) return TargetArch.arm32;
    } catch (_) {
      // 忽略
    }
    return TargetArch.any;
  }

  @override
  Future<void> flashModule(String path) async {
    if (!Platform.isAndroid) {
      throw Exception('仅 Android 支持刷入 Magisk/KernelSU 模块');
    }
    // _quote 已做单引号转义，注意不要再包一层引号（否则路径带字面引号必失败）
    final target = _quote(path);
    // su 环境的 PATH 未必包含各家管理器的二进制目录，统一追加
    const pathFix =
        r'export PATH="$PATH:/data/adb/ksu/bin:/data/adb/magisk:/data/adb/ap";';
    const cmds = [
      'ksud module install', // KernelSU
      'magisk --install-module', // Magisk
      'apd module install', // APatch
      '/data/adb/ksu/bin/ksud module install', // KernelSU（绝对路径兜底）
      '/data/adb/magisk/magisk --install-module', // Magisk（绝对路径兜底）
    ];

    void emit(String line) {
      AppLog.info('[模块] $line');
      ModuleInstallConsole.emit(line);
    }

    emit('开始刷入模块：$path');
    final failures = <String>[];
    for (final c in cmds) {
      final full = '$pathFix $c $target';
      emit('\$ su -c "$c <模块包>"');
      try {
        final proc = await Process.start('su', ['-c', full]);
        final out = proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach(emit);
        final err = proc.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach(emit);
        final code = await proc.exitCode;
        await out;
        await err;
        if (code == 0) {
          emit('✔ 模块刷入成功（$c）');
          return;
        }
        failures.add('$c → 退出码 $code');
        emit('✘ 失败（$c，退出码 $code）');
      } catch (e) {
        failures.add('$c → $e');
        emit('✘ 失败（$c）：$e');
      }
    }
    throw Exception('模块刷入失败：未找到可用的管理器或刷入出错。\n'
        '请确认已安装 Magisk / KernelSU / APatch 之一，且已授予本应用 root 权限。\n'
        '尝试记录：\n- ${failures.join('\n- ')}');
  }

  @override
  Future<Map<String, String>> androidModuleProps() async {
    if (!Platform.isAndroid) return const {};
    const cmd = r'for d in /data/adb/modules/*/; do i=$(basename "$d"); '
        r'echo "@@$i"; cat "$d/module.prop" 2>/dev/null; done';
    return parseModuleSections(await _shellOutput(cmd));
  }

  @override
  Future<Map<String, String>> androidPackageVersions() async {
    if (!Platform.isAndroid) return const {};
    return parsePackageVersions(await _shellOutput('dumpsys package'));
  }

  /// 依次尝试 root / Shizuku / 普通 shell 执行命令，返回 stdout（均失败返回空串）
  Future<String> _shellOutput(String cmd) async {
    const candidates = [
      ['su', '-c'],
      ['shizuku', '-c'],
      ['sh', '-c'],
    ];
    for (final c in candidates) {
      try {
        final r = await Process.run(c.first, [...c.sublist(1), cmd]);
        final out = (r.stdout as String?) ?? '';
        if (r.exitCode == 0 && out.trim().isNotEmpty) return out;
      } catch (_) {
        // 换下一种方式
      }
    }
    return '';
  }

  @override
  Future<void> dockerUpdate(String image,
      {String? containerName, String? runArgs}) async {
    await _run('docker', ['pull', image]);
    if (containerName != null && containerName.isNotEmpty) {
      await _run('docker', ['stop', containerName]);
      await _run('docker', ['rm', containerName]);
      final recreate = [
        'run',
        '-d',
        '--name',
        containerName,
        ...?_splitArgs(runArgs),
        image,
      ];
      await _run('docker', recreate);
    }
  }

  @override
  Future<void> notifySystem(
      String title, String body, NotificationLevel level) async {
    try {
      if (Platform.isWindows) {
        await _showWindowsToast(title, body);
      } else if (Platform.isLinux) {
        final r = await Process.run('notify-send', [title, body]);
        if (r.exitCode != 0) print('[$title] $body');
      } else {
        print('[$title] $body');
      }
    } catch (_) {
      print('[$title] $body');
    }
  }

  @override
  Future<void> openFolder(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else {
      throw UnsupportedError('当前平台不支持打开文件夹');
    }
  }

  @override
  Future<void> openExternal(String url) async {
    if (Platform.isWindows) {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url],
          mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
    } else {
      throw UnsupportedError('当前平台不支持外部浏览器打开');
    }
  }

  @override
  Future<void> launchPortableApp(
      {required String installDir, required String file, String? cmd}) async {
    final c = cmd?.trim() ?? '';
    // 命令非空：作为完整命令在安装目录下执行（覆盖默认行为）
    if (c.isNotEmpty) {
      final shell = Platform.isWindows ? 'cmd' : 'sh';
      final args =
          Platform.isWindows ? ['/c', c] : ['-c', c];
      await Process.start(shell, args,
          workingDirectory: installDir, mode: ProcessStartMode.detached);
      return;
    }
    final exe = p.join(installDir, file);
    if (Platform.isLinux) {
      // 确保可执行权限（新解压的文件可能没有 +x）
      try {
        await Process.run('chmod', ['+x', exe]);
      } catch (_) {}
    }
    await Process.start(exe, [],
        workingDirectory: installDir, mode: ProcessStartMode.detached);
  }

  Future<void> _showWindowsToast(String title, String body) async {
    const script = '''
\$ErrorActionPreference='SilentlyContinue'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
\$t = [System.Environment]::GetEnvironmentVariable('GRKU_T')
\$b = [System.Environment]::GetEnvironmentVariable('GRKU_B')
\$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$texts = \$template.GetElementsByTagName('text')
\$texts.Item(0).AppendChild(\$template.CreateTextNode(\$t)) | Out-Null
\$texts.Item(1).AppendChild(\$template.CreateTextNode(\$b)) | Out-Null
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('grku').Show(\$template)
''';
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      environment: {'GRKU_T': title, 'GRKU_B': body},
    );
    if (r.exitCode != 0) print('[$title] $body');
  }

  /// 运行需要管理员权限的命令：Windows 下尝试提权，其它平台直接运行
  Future<ProcessResult> _runElevated(String exe, List<String> args) async {
    if (!Platform.isWindows) {
      final r = await Process.run(exe, args);
      _check(r, '$exe ${args.join(' ')}');
      return r;
    }
    final psArgs = args.map((a) => '"$a"').join(',');
    final script =
        'Start-Process -FilePath "$exe" -ArgumentList $psArgs -Verb RunAs -Wait -PassThru';
    final r = await Process.run('powershell',
        ['-NoProfile', '-Command', script]);
    if (r.exitCode != 0) {
      throw Exception('提权执行失败: $exe（请以管理员身份运行）: ${r.stderr}');
    }
    return r;
  }

  Future<ProcessResult> _run(String exe, List<String> args) async {
    final r = await Process.run(exe, args);
    _check(r, '$exe ${args.join(' ')}');
    return r;
  }

  void _check(ProcessResult r, String what) {
    if (r.exitCode != 0) {
      throw Exception('命令执行失败: $what\n${r.stderr}');
    }
  }

  /// 对含空格/单引号的文件路径做 shell 安全转义
  String _quote(String p) => "'${p.replaceAll("'", r"'\''")}'";

  List<String>? _splitArgs(String? s) {
    if (s == null || s.isEmpty) return null;
    return s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  }
}
