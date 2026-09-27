/// 「更多版本」页面：分页浏览仓库历史 Release（每页 10 个），
/// 每个版本一张卡片：版本号、发布时间、changelog 与「下载」按钮。
/// 下载流程与主界面更新完全一致（匹配资产 → 下载 → 安装/刷入 → 更新已装版本）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/github/release_model.dart';
import '../../core/config/models.dart';
import '../../core/download/download_manager.dart';
import '../../core/updater/update_service.dart';
import '../providers/app_providers.dart';
import '../providers/check_providers.dart';
import '../widgets/module_terminal.dart';

class ReleasesScreen extends ConsumerStatefulWidget {
  const ReleasesScreen({super.key, required this.repo});
  final RepoConfig repo;

  @override
  ConsumerState<ReleasesScreen> createState() => _ReleasesScreenState();
}

class _ReleasesScreenState extends ConsumerState<ReleasesScreen> {
  static const _pageSize = 10;

  List<Release>? _releases;
  String? _error;
  int _page = 0;
  String? _downloading; // 正在下载/安装的版本 tag（null = 空闲）
  double? _progress;
  String _status = '';

  RepoConfig get _repo => ref
      .read(configProvider)
      .repos
      .firstWhere((e) => e.fullName == widget.repo.fullName,
          orElse: () => widget.repo);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      if (_releases == null) _releases = null;
    });
    try {
      final list =
          await ref.read(updateServiceProvider).listReleases(widget.repo);
      if (!mounted) return;
      setState(() => _releases = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  /// 下载/安装指定版本（与主界面更新流程一致）
  Future<void> _download(Release rel) async {
    if (_downloading != null) return;
    final r = _repo;
    final downloads = ref.read(downloadsProvider.notifier);
    final token = downloads.start(r.fullName);
    ModuleTerminalHandle? terminal;
    setState(() {
      _downloading = rel.tagName;
      _progress = null;
      _status = '准备下载';
    });
    try {
      final svc = ref.read(updateServiceProvider);
      final c = await svc.checkRelease(r, rel);
      if (c.match == null) {
        _snack('版本 ${rel.tagName} 没有匹配当前平台的资产，请调整匹配规则');
        return;
      }
      final isModule = c.match!.rule.strategy == UpdateStrategy.module;
      await svc.update(c, cancelToken: token,
          onProgress: (rc, t) {
            if (!mounted) return;
            setState(() {
              _progress = t > 0 ? rc / t : null;
              _status = t > 0
                  ? '下载 ${(rc / t * 100).toStringAsFixed(0)}%'
                  : '下载 ${_fmtBytes(rc)}';
            });
          },
          // 下载完成（安装前）：模块刷入打开终端窗口；APK 提取信息
          onDownloaded: (file) async {
            if (isModule && mounted) {
              terminal = openModuleTerminal(context);
            }
            await fetchApkInfoForRepo(ref, r, apkPath: file.path);
          });
      if (!mounted) return;
      ref
          .read(configProvider.notifier)
          .updateRepo(ref.read(configProvider.notifier).freshRepo(r).copyWith(
              lastInstalledTag: c.release.tagName));
      await ref
          .read(checkProvider.notifier)
          .learnIdentityFor(r, c.release.tagName);
      _snack('完成 → ${rel.tagName}');
    } on InstallFailedException {
      _snack('安装失败（已下载，可到主界面重试安装）');
    } on DownloadCancelled {
      _snack('已暂停');
    } catch (e) {
      _snack('失败: $e');
    } finally {
      downloads.finish(r.fullName, '结束');
      if (mounted) {
        setState(() => _downloading = null);
      }
      await terminal?.close();
    }
  }

  String _fmtBytes(int bytes) {
    const kb = 1024.0;
    const mb = 1024.0 * 1024.0;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _fmtDate(DateTime? t) =>
      t == null ? '' : '${t.year}-${t.month.toString().padLeft(2, '0')}'
          '-${t.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final releases = _releases;
    return Scaffold(
      appBar: AppBar(title: Text('更多版本 · ${widget.repo.fullName}')),
      body: releases == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('加载失败：$_error',
                        style: const TextStyle(color: Color(0xFFF87171))),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _load, child: const Text('重试')),
                  ],
                ))
              : _buildList(releases!),
    );
  }

  Widget _buildList(List<Release> releases) {
    final pageCount = (releases.length / _pageSize).ceil();
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final slice =
        releases.skip(page * _pageSize).take(_pageSize).toList();
    return Column(
      children: [
        Expanded(
          child: slice.isEmpty
              ? const Center(child: Text('该仓库还没有任何 Release'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final rel in slice)
                        _releaseCard(rel, downloading: _downloading != null),
                    ],
                  ),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: page > 0
                      ? () => setState(() => _page = page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('第 ${page + 1} / ${pageCount == 0 ? 1 : pageCount} 页'
                    ' · 共 ${releases.length} 个版本',
                    style: const TextStyle(fontSize: 13)),
                IconButton(
                  onPressed: page < pageCount - 1
                      ? () => setState(() => _page = page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _releaseCard(Release rel, {required bool downloading}) {
    final busy = _downloading == rel.tagName;
    final body = rel.body?.trim() ?? '';
    final canDownload = !downloading && _downloading == null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(rel.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                if (rel.prerelease)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C2D12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('预发布',
                        style: TextStyle(fontSize: 11)),
                  ),
                const SizedBox(width: 8),
                Text(_fmtDate(rel.publishedAt),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF94A3B8))),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              _Changelog(text: body),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    busy ? _status : '',
                    style: const TextStyle(fontSize: 12,
                        color: Color(0xFF94A3B8)),
                  ),
                ),
                if (busy && _progress != null)
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(value: _progress),
                  )
                else if (busy)
                  const SizedBox(
                      width: 120,
                      child: LinearProgressIndicator()),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: canDownload ? () => _download(rel) : null,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(busy ? '进行中' : '下载'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Changelog 文本：默认折叠显示 6 行，点击展开/收起
class _Changelog extends StatefulWidget {
  const _Changelog({required this.text});
  final String text;

  @override
  State<_Changelog> createState() => _ChangelogState();
}

class _ChangelogState extends State<_Changelog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.text,
        maxLines: _expanded ? null : 6,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1),
            height: 1.4),
      ),
    );
  }
}
