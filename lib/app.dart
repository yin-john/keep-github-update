import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_paths.dart';
import 'core/config/models.dart';
import 'core/scheduler/check_schedule.dart';
import 'ui/providers/app_providers.dart';
import 'ui/providers/check_providers.dart';
import 'ui/screens/downloads_screen.dart';
import 'ui/screens/repo_list_screen.dart';
import 'ui/screens/settings_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    // 用 fromSeed 生成「完整」的暗色 ColorScheme，
    // 避免 M3 的其它表面色（输入框填充、下拉菜单、磁贴等）落到浅色/灰白。
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF3B82F6),
      secondary: const Color(0xFF22D3EE),
      surface: const Color(0xFF1E293B),
      // 显式指定 M3 各级「表面容器」为暗色，
      // 否则输入框填充、下拉菜单、卡片等会落到浅色（灰白）。
      surfaceContainerLowest: const Color(0xFF0F172A),
      surfaceContainerLow: const Color(0xFF172033),
      surfaceContainer: const Color(0xFF1A2334),
      surfaceContainerHigh: const Color(0xFF1E293B),
      surfaceContainerHighest: const Color(0xFF243044),
    );
    return MaterialApp(
      title: 'GRKU',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        canvasColor: const Color(0xFF1E293B),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0F172A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  final _pages = const [
    RepoListScreen(),
    DownloadsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkStartupPermissions();
      _bootstrapBackground();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 桌面端：开启后台保活后，关闭窗口不退出应用（继续按间隔检测）
  @override
  Future<ui.AppExitResponse> didRequestAppExit() async {
    if (!Platform.isWindows && !Platform.isLinux) {
      return ui.AppExitResponse.exit;
    }
    if (!ref.read(configProvider).backgroundKeepAlive) {
      return ui.AppExitResponse.exit;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('后台保活已开启：应用将继续按设定的间隔检测更新。'
            '如需退出，请先在「设置」关闭后台保活。'),
        duration: Duration(seconds: 4),
      ));
    }
    return ui.AppExitResponse.cancel;
  }

  /// 启动时按配置启用后台保活与自动检测
  ///
  /// 必须等配置从磁盘加载完成再操作：配置是异步加载的，若先用默认值（未开启）
  /// 去「停服务」、紧接着又按加载后的值（已开启）去「启服务」，Android 侧会先处理
  /// 停止动作而始终没有调用 startForeground()，系统随即抛
  /// RemoteServiceException: Context.startForegroundService() did not then call
  /// Service.startForeground()，表现为开启常驻通知后启动即崩溃、无法打开。
  Future<void> _bootstrapBackground() async {
    try {
      await ref.read(configProvider.notifier).ready;
    } catch (_) {
      // 配置加载失败时按当前（默认）值处理
    }
    if (!mounted) return;
    final cfg = ref.read(configProvider);
    _syncScheduler(cfg.checkIntervalMinutes);
    await _applyKeepAlive(cfg.backgroundKeepAlive);
  }

  /// 按全局间隔启停自动检测调度
  void _syncScheduler(int intervalMinutes) {
    final scheduler = ref.read(schedulerProvider);
    if (autoCheckEnabled(intervalMinutes)) {
      scheduler.start();
    } else {
      scheduler.stop();
    }
  }

  /// 常驻通知栏 + 后台保活
  ///
  /// - Android：原生前台服务（常驻通知，进程保活）
  /// - Windows / Linux：无系统级常驻通知，改为「关闭窗口不退出」的保活，
  ///   并在每次后台检测有结果时由系统通知提示
  Future<void> _applyKeepAlive(bool enabled) async {
    if (!mounted) return;
    final env = ref.read(androidEnvProvider);
    try {
      if (env.isAndroid) {
        if (!enabled) {
          await env.stopBackgroundService();
          return;
        }
        final ok = await env.startBackgroundService(
          title: 'GRKU 后台运行中',
          text: '正在按设定的间隔检测更新',
        );
        var running = ok;
        if (ok) {
          // 稍等片刻确认服务真的进入前台；起不来就自动关闭开关，
          // 否则该开关是持久化的，会造成每次启动都失败
          await Future<void>.delayed(const Duration(milliseconds: 700));
          if (!mounted) return;
          running = await env.isBackgroundServiceRunning();
        }
        if (!running) {
          ref.read(configProvider.notifier).setConfig(
              ref.read(configProvider).copyWith(backgroundKeepAlive: false));
          _snack('常驻通知/后台保活启动失败，已自动关闭该开关'
              '（请确认已允许通知权限后重试）');
        }
        return;
      }
      if (enabled) {
        _snack('后台保活已开启：关闭窗口时应用不会退出（当前平台无常驻通知栏）');
      }
    } catch (e) {
      // 后台能力不可用时不影响前台使用
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    // 可能由 provider 变化触发（构建期间），推迟到帧末提示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    });
  }

  /// 开屏检查：Android 默认下载目录在公共存储，需要「所有文件访问」权限；
  /// 未授权时询问去授权，或改用应用私有目录（无需授权）。
  Future<void> _checkStartupPermissions() async {
    final env = ref.read(androidEnvProvider);
    if (!env.isAndroid) return;
    try {
      if (await env.hasStoragePermission()) return;
      final cfg = ref.read(configProvider);
      // 用户已显式配置过下载目录则不再打扰
      if (cfg.downloadDir != null && cfg.downloadDir!.isNotEmpty) return;
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要存储权限'),
          content: Text('默认下载目录位于公共存储：\n${defaultDownloadDir()}\n\n'
              '未获得「所有文件访问」权限时该目录不可读写。\n'
              '可前往系统设置授权，或改用应用私有目录（无需授权，但其它应用不易访问）。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('用私有目录'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      if (go == true) {
        await env.requestStoragePermission();
      } else {
        ref
            .read(configProvider.notifier)
            .setConfig(cfg.copyWith(downloadDir: fallbackDownloadDir()));
      }
    } catch (_) {
      // 开屏检查失败不阻塞启动
    }
  }

  @override
  Widget build(BuildContext context) {
    // 配置变化时同步后台能力（仅关注相关字段，避免频繁重启）
    ref.listen<AppConfig>(configProvider, (prev, next) {
      if (prev?.checkIntervalMinutes != next.checkIntervalMinutes) {
        _syncScheduler(next.checkIntervalMinutes);
      }
      if (prev?.backgroundKeepAlive != next.backgroundKeepAlive) {
        _applyKeepAlive(next.backgroundKeepAlive);
      }
    });
    final isWide = MediaQuery.of(context).size.width >= 720;
    return Scaffold(
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                        icon: Icon(Icons.list), label: Text('仓库')),
                    NavigationRailDestination(
                        icon: Icon(Icons.download), label: Text('下载')),
                    NavigationRailDestination(
                        icon: Icon(Icons.settings),
                        label: Text('设置')),
                  ],
                ),
                const VerticalDivider(width: 1),
                // IndexedStack 保活所有页面，切换 Tab 时各自状态不丢失
                Expanded(
                  child: IndexedStack(index: _index, children: _pages),
                ),
              ],
            )
          : IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: isWide
          ? null
          : BottomNavigationBar(
              currentIndex: _index,
              onTap: (i) => setState(() => _index = i),
              items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.list), label: '仓库'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.download), label: '下载'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.settings), label: '设置'),
              ],
            ),
    );
  }
}
