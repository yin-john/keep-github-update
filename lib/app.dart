import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_paths.dart';
import 'ui/providers/app_providers.dart';
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

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  final _pages = const [
    RepoListScreen(),
    DownloadsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkStartupPermissions());
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
