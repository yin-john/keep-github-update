import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_paths.dart';
import '../../core/config/models.dart';
import '../../core/download/download_manager.dart';
import '../../core/updater/update_service.dart';
import '../providers/app_providers.dart';
import '../widgets/repo_card.dart';
import 'repo_edit_screen.dart';

class RepoListScreen extends ConsumerStatefulWidget {
  const RepoListScreen({super.key});

  @override
  ConsumerState<RepoListScreen> createState() => _RepoListScreenState();
}

class _RepoListScreenState extends ConsumerState<RepoListScreen> {
  final Map<String, String> _status = {};
  final Map<String, bool?> _hasUpdate = {};
  final Map<String, String> _latest = {};
  final Map<String, CancelToken> _cancel = {};
  final Set<String> _selected = {}; // 批量更新勾选
  final Map<String, UpdateCheck> _checks = {}; // 最近检测结果（重试安装复用）
  final Set<String> _installRetry = {}; // 已下载但安装失败、可重试的仓库
  bool _busy = false;

  /// Windows/Linux 下提供「打开文件夹」
  bool get _canOpenFolder => Platform.isWindows || Platform.isLinux;

  /// 对应目录：优先安装目录，其次该仓库的下载目录
  String _folderFor(RepoConfig r) =>
      (r.installDir != null && r.installDir!.isNotEmpty)
          ? r.installDir!
          : repoDownloadDir(r.owner, r.repo,
              baseDir: ref.read(configProvider).downloadDir);

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  String _fmtSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '—';
    const kb = 1024.0;
    const mb = 1024.0 * 1024.0;
    if (bytesPerSec >= mb) {
      return '${(bytesPerSec / mb).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSec >= kb) {
      return '${(bytesPerSec / kb).toStringAsFixed(0)} KB/s';
    }
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  }

  /// 未匹配到资产时，列出该版本的实际产物，便于修正匹配正则
  Future<void> _showNoMatchDialog(
      RepoConfig r, String tag, List<String> assets) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未找到匹配的资产'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${r.fullName} 最新版本 $tag 的产物：'),
              const SizedBox(height: 6),
              if (assets.isEmpty)
                const Text('（该版本没有任何产物）')
              else
                ...assets.map((a) => SelectableText('• $a')),
              const SizedBox(height: 10),
              const Text('请调整该仓库的「文件名匹配正则」，使其能匹配上述文件。',
                  style: TextStyle(color: Color(0xFF94A3B8))),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  /// 把设备上读到的真实已装版本同步进配置（供列表/CLI 显示）
  void _syncInstalled(RepoConfig r, UpdateCheck c) {
    final v = c.installedVersion;
    if (v == null || v.isEmpty || v == r.lastInstalledTag) return;
    ref
        .read(configProvider.notifier)
        .updateRepo(r.copyWith(lastInstalledTag: v));
  }

  /// 依据设备上读到的版本反查并补全包名 / 模块 ID
  Future<void> _learnIdentity(RepoConfig r, UpdateCheck c) async {
    final hasPkg = r.packageName != null && r.packageName!.isNotEmpty;
    final hasModule = r.moduleId != null && r.moduleId!.isNotEmpty;
    if (hasPkg || hasModule) return;
    final tag = c.installedVersion ?? r.lastInstalledTag;
    if (tag == null || tag.isEmpty) return;
    try {
      final id = await ref.read(updateServiceProvider).detectIdentity(r, tag);
      if (id == null) return;
      if (id.packageName == null && id.moduleId == null) return;
      ref.read(configProvider.notifier).updateRepo(
          r.copyWith(packageName: id.packageName, moduleId: id.moduleId));
    } catch (_) {
      // 反查失败不影响检测
    }
  }

  Future<void> _check(RepoConfig r) async {
    setState(() => _busy = true);
    try {
      final svc = ref.read(updateServiceProvider);
      final c = await svc.check(r);
      _checks[r.fullName] = c;
      setState(() {
        _latest[r.fullName] = c.release.tagName;
        _hasUpdate[r.fullName] = c.match == null ? null : c.hasUpdate;
        _status[r.fullName] = describeCheck(c);
      });
      _syncInstalled(r, c);
      await _learnIdentity(r, c);
      if (c.hasUpdate) {
        await ref.read(systemNotifierProvider).show(
            '${r.fullName} 有可用更新',
            '检测到适用于当前平台的新版本',
            NotificationLevel.info);
      }
    } catch (e) {
      setState(() => _status[r.fullName] = '检测失败: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// 批量检测指定仓库（「检测全部」与「检测所选」共用）
  Future<void> _checkMany(List<RepoConfig> targets) async {
    if (targets.isEmpty) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(updateServiceProvider);
      for (final r in targets) {
        try {
          final c = await svc.check(r);
          setState(() {
            _latest[r.fullName] = c.release.tagName;
            _hasUpdate[r.fullName] = c.match == null ? null : c.hasUpdate;
            _status[r.fullName] = describeCheck(c);
          });
          _syncInstalled(r, c);
          await _learnIdentity(r, c);
        } catch (e) {
          setState(() => _status[r.fullName] = '检测失败: $e');
        }
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  List<RepoConfig> _selectedRepos() => ref
      .read(configProvider)
      .repos
      .where((r) => _selected.contains(r.fullName))
      .toList();

  Future<void> _scanAll() => _checkMany(ref.read(configProvider).repos);

  /// 检测所选仓库
  Future<void> _checkSelected() => _checkMany(_selectedRepos());

  /// 全选 / 取消全选
  void _toggleAll(List<RepoConfig> repos) {
    setState(() {
      if (repos.isNotEmpty && _selected.length == repos.length) {
        _selected.clear();
      } else {
        _selected.addAll(repos.map((e) => e.fullName));
      }
    });
  }

  /// 反选
  void _invertSelection(List<RepoConfig> repos) {
    setState(() {
      _selected
        ..clear()
        ..addAll(repos
            .map((e) => e.fullName)
            .where((n) => !_selected.contains(n)));
    });
  }

  /// 清空仓库（可选同时删除已下载文件）
  Future<void> _clearAllRepos() async {
    final repos = ref.read(configProvider).repos;
    if (repos.isEmpty) return;
    var deleteFiles = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('清空仓库'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('将移除全部 ${repos.length} 个仓库配置，此操作不可撤销。'),
              const SizedBox(height: 4),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: deleteFiles,
                onChanged: (v) => setDlg(() => deleteFiles = v ?? false),
                title: const Text('同时删除已下载的文件'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await ref
        .read(configProvider.notifier)
        .clearRepos(deleteDownloads: deleteFiles);
    if (!mounted) return;
    setState(_selected.clear);
    _snack('已清空 ${repos.length} 个仓库');
  }

  /// 勾选若干仓库后出现的操作栏：检测所选 / 更新所选
  Widget _selectionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _checkSelected,
            icon: const Icon(Icons.travel_explore, size: 18),
            label: Text('检测所选 (${_selected.length})'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _updateSelected,
            icon: const Icon(Icons.system_update_alt, size: 18),
            label: Text('更新所选 (${_selected.length})'),
          ),
        ],
      ),
    );
  }

  /// 右上角「⋮」菜单：全选 / 反选 / 清空仓库
  Widget _overflowMenu(List<RepoConfig> repos) {
    final allSelected = repos.isNotEmpty && _selected.length == repos.length;
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      onSelected: (v) {
        if (v == 'all') {
          _toggleAll(repos);
        } else if (v == 'invert') {
          _invertSelection(repos);
        } else if (v == 'clear') {
          _clearAllRepos();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'all',
          enabled: repos.isNotEmpty,
          child: Row(children: [
            Icon(allSelected ? Icons.remove_done : Icons.done_all, size: 18),
            const SizedBox(width: 8),
            Text(allSelected ? '取消全选' : '全选'),
          ]),
        ),
        PopupMenuItem(
          value: 'invert',
          enabled: repos.isNotEmpty,
          child: const Row(children: [
            Icon(Icons.swap_horiz, size: 18),
            SizedBox(width: 8),
            Text('反选'),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'clear',
          enabled: repos.isNotEmpty,
          child: const Row(children: [
            Icon(Icons.delete_sweep, size: 18, color: Color(0xFFF87171)),
            SizedBox(width: 8),
            Text('清空仓库', style: TextStyle(color: Color(0xFFF87171))),
          ]),
        ),
      ],
    );
  }

  /// 更新单个仓库
  Future<void> _update(RepoConfig r) async {
    setState(() => _busy = true);
    try {
      await _updateOne(r);
    } finally {
      setState(() => _busy = false);
    }
  }

  /// 一键更新所选（可多选）
  Future<void> _updateSelected() async {
    final targets = _selectedRepos();
    if (targets.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final r in targets) {
        await _updateOne(r);
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _updateOne(RepoConfig r) async {
    final downloads = ref.read(downloadsProvider.notifier);
    final token = downloads.start(r.fullName);
    _cancel[r.fullName] = token;
    try {
      final svc = ref.read(updateServiceProvider);
      final c = await svc.check(r);
      _checks[r.fullName] = c;
      setState(() {
        _latest[r.fullName] = c.release.tagName;
        _hasUpdate[r.fullName] = c.match == null ? null : c.hasUpdate;
      });
      if (c.match == null) {
        setState(() => _status[r.fullName] = describeCheck(c));
        downloads.finish(r.fullName, '未找到匹配的资产');
        if (mounted) {
          await _showNoMatchDialog(r, c.release.tagName,
              c.release.assets.map((a) => a.name).toList());
        }
        return;
      }
      if (!c.hasUpdate) {
        final s = describeCheck(c);
        setState(() => _status[r.fullName] = s);
        downloads.finish(r.fullName, s);
        return;
      }

      var lastRc = 0;
      var lastAt = DateTime.now();
      var speed = 0.0;
      await svc.update(c, cancelToken: token, onProgress: (rc, t) {
        final now = DateTime.now();
        final ms = now.difference(lastAt).inMilliseconds;
        if (ms >= 400 || (t > 0 && rc >= t)) {
          speed = ms > 0 ? (rc - lastRc) * 1000 / ms : 0;
          lastRc = rc;
          lastAt = now;
          final pct = t > 0 ? (rc / t * 100).toStringAsFixed(0) : '?';
          final ratio = t > 0 ? rc / t : null;
          setState(() =>
              _status[r.fullName] = '下载 $pct% · ${_fmtSpeed(speed)}');
          downloads.progress(r.fullName,
              progress: ratio, speed: speed, status: '下载中');
        }
      });
      ref
          .read(configProvider.notifier)
          .updateRepo(r.copyWith(lastInstalledTag: c.release.tagName));
      // 更新后设备上的版本即 tag，据此反查补全包名/模块 ID
      await _learnIdentity(r, c);
      setState(() {
        _installRetry.remove(r.fullName);
        _status[r.fullName] = '完成 → ${c.release.tagName}';
        _hasUpdate[r.fullName] = false;
      });
      downloads.finish(r.fullName, '完成 → ${c.release.tagName}');
    } on InstallFailedException catch (e) {
      // 已下载完成，仅安装失败 → 提供「重试安装」
      setState(() {
        _installRetry.add(r.fullName);
        _status[r.fullName] = '安装失败（已下载，可重试安装）：${e.message}';
      });
      downloads.finish(r.fullName, '安装失败，可重试');
    } on DownloadCancelled {
      setState(() => _status[r.fullName] = '已暂停（可再点更新继续）');
      downloads.finish(r.fullName, '已暂停');
    } catch (e) {
      setState(() => _status[r.fullName] = '失败: $e');
      downloads.finish(r.fullName, '失败: $e');
    } finally {
      _cancel.remove(r.fullName);
    }
  }

  /// 仅重试安装：复用已下载的文件，不重新下载
  Future<void> _retryInstall(RepoConfig r) async {
    setState(() => _busy = true);
    final downloads = ref.read(downloadsProvider.notifier);
    final token = downloads.start(r.fullName);
    _cancel[r.fullName] = token;
    try {
      final svc = ref.read(updateServiceProvider);
      final c = _checks[r.fullName] ?? await svc.check(r);
      final file = await svc.lastDownloadedFile(r,
          downloadDir: ref.read(configProvider).downloadDir);
      if (file == null) {
        setState(() => _status[r.fullName] = '未找到已下载的文件，请点「更新」重新下载');
        downloads.finish(r.fullName, '无已下载文件');
        return;
      }
      await svc.applyDownloaded(c, file);
      ref
          .read(configProvider.notifier)
          .updateRepo(r.copyWith(lastInstalledTag: c.release.tagName));
      setState(() {
        _installRetry.remove(r.fullName);
        _hasUpdate[r.fullName] = false;
        _status[r.fullName] = '重试安装成功 → ${c.release.tagName}';
      });
      downloads.finish(r.fullName, '重试安装成功');
    } on InstallFailedException catch (e) {
      setState(() => _status[r.fullName] = '安装仍失败（可再重试）：${e.message}');
      downloads.finish(r.fullName, '安装失败');
    } catch (e) {
      setState(() => _status[r.fullName] = '重试失败: $e');
      downloads.finish(r.fullName, '重试失败');
    } finally {
      _cancel.remove(r.fullName);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFolder(RepoConfig r) async {
    final candidates = <String>[
      if (r.installDir != null && r.installDir!.isNotEmpty) r.installDir!,
      repoDownloadDir(r.owner, r.repo,
          baseDir: ref.read(configProvider).downloadDir),
    ];
    try {
      // 优先打开已存在的目录（安装目录 → 下载目录）
      for (final c in candidates) {
        if (await Directory(c).exists()) {
          await ref.read(platformBridgeProvider).openFolder(c);
          return;
        }
      }
      // 都不存在：打开最近的已存在上级目录，不新建空目录
      final fallback = _nearestExisting(candidates.first);
      if (fallback != null) {
        await ref.read(platformBridgeProvider).openFolder(fallback);
        _snack('尚无文件，已打开上级目录：$fallback');
        return;
      }
      _snack('目录不存在：${candidates.first}');
    } catch (e) {
      _snack('打开文件夹失败：$e');
    }
  }

  /// 返回最近的已存在上级目录（逐级向上，直到根）
  String? _nearestExisting(String path) {
    var cur = path;
    while (true) {
      if (Directory(cur).existsSync()) return cur;
      final parent = Directory(cur).parent.path;
      if (parent == cur) return null;
      cur = parent;
    }
  }

  Future<void> _clearDownloads(RepoConfig r) async {
    final dir = repoDownloadDir(r.owner, r.repo,
        baseDir: ref.read(configProvider).downloadDir);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空下载'),
        content: Text('将删除该仓库的下载目录：\n$dir'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await clearRepoDownloads(r.owner, r.repo,
          baseDir: ref.read(configProvider).downloadDir);
      _snack('已清空下载：$dir');
    } catch (e) {
      _snack('清空失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repos = ref.watch(configProvider).repos;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _selected.isEmpty ? '仓库' : '仓库 · 已选 ${_selected.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.travel_explore),
            tooltip: _selected.isEmpty ? '检测全部' : '检测所选',
            onPressed:
                _busy ? null : (_selected.isEmpty ? _scanAll : _checkSelected),
          ),
          _overflowMenu(repos),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'repo-add',
        tooltip: '添加仓库',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RepoEditScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // 仅在勾选后显示「检测所选 / 更新所选」操作栏
          if (_selected.isNotEmpty) ...[
            _selectionBar(),
            const Divider(height: 1),
          ],
          Expanded(
            child: repos.isEmpty
                ? const Center(
                    child: Text('暂无仓库，点右下角 + 添加',
                        style: TextStyle(color: Color(0xFF94A3B8))))
                : ListView.builder(
              itemCount: repos.length,
              itemBuilder: (_, i) {
                final r = repos[i];
                return RepoCard(
                  repo: r,
                  status: _status[r.fullName],
                  hasUpdate: _hasUpdate[r.fullName],
                  latestTag: _latest[r.fullName],
                  folderPath: _canOpenFolder ? _folderFor(r) : null,
                  selected: _selected.contains(r.fullName),
                  onSelected: (v) => setState(() {
                    if (v == true) {
                      _selected.add(r.fullName);
                    } else {
                      _selected.remove(r.fullName);
                    }
                  }),
                  onEdit: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => RepoEditScreen(repo: r)),
                  ),
                  onCheck: () => _check(r),
                  onUpdate: () => _update(r),
                  onOpenFolder: () => _openFolder(r),
                  onCancel: _cancel.containsKey(r.fullName)
                      ? () => ref
                          .read(downloadsProvider.notifier)
                          .cancel(r.fullName)
                      : null,
                  onClearDownloads: () => _clearDownloads(r),
                  onRetryInstall: _installRetry.contains(r.fullName)
                      ? () => _retryInstall(r)
                      : null,
                  onDelete: () async {
                    await ref
                        .read(configProvider.notifier)
                        .removeRepo(r.fullName);
                    setState(() => _selected.remove(r.fullName));
                  },
                );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
