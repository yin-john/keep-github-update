import 'package:flutter/material.dart';
import '../../core/config/models.dart';
import '../../core/config/repo_display.dart';
import 'repo_avatar.dart';

class RepoCard extends StatelessWidget { // 非空则显示「重试安装」（已下载但安装失败）

  const RepoCard({
    super.key,
    required this.repo,
    this.status,
    this.hasUpdate,
    this.latestTag,
    this.folderPath,
    this.onEdit,
    this.onCheck,
    this.onUpdate,
    this.onDelete,
    this.onOpenFolder,
    this.onCancel,
    this.onClearDownloads,
    this.selected = false,
    this.onSelected,
    this.onRetryInstall,
    this.onLaunch,
    this.onMoreVersions,
    this.onRepoDetails,
  });
  final RepoConfig repo;
  final String? status; // 更新状态文本
  final bool? hasUpdate; // 是否可更新（用于状态着色）
  final String? latestTag; // 仓库最新版本
  final String? folderPath; // 非空且在受支持平台时显示「打开文件夹」按钮
  final VoidCallback? onEdit;
  final VoidCallback? onCheck;
  final VoidCallback? onUpdate;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onCancel; // 非空表示正在下载，可中断
  final VoidCallback? onClearDownloads; // 清空该仓库下载
  final bool selected; // 是否被勾选（批量更新用）
  final ValueChanged<bool?>? onSelected; // 非空则显示勾选框
  final VoidCallback? onRetryInstall;
  final VoidCallback? onLaunch; // 非空则显示「启动」按钮（Android 已知包名 / 桌面已配置启动文件）
  final VoidCallback? onMoreVersions; // 「更多版本」菜单项（历史版本下载页）
  final VoidCallback? onRepoDetails; // 「仓库详情」菜单项（仓库地址 + 外部浏览器）

  Color get _statusColor {
    if (hasUpdate == true) return const Color(0xFF22C55E); // 可更新：绿
    if (hasUpdate == false) return const Color(0xFFF59E0B); // 已最新：琥珀
    return const Color(0xFF94A3B8); // 未知/失败：灰
  }

  @override
  Widget build(BuildContext context) {
    // 有自定义名称 / 自动获取到的软件名称时，第二行以次一级字体显示「作者/仓库名」
    final title = resolveRepoTitle(
      fullName: repo.fullName,
      displayName: repo.displayName,
      apkLabel: repo.apkLabel,
    );
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (onSelected != null)
                  Checkbox(
                    value: selected,
                    onChanged: onSelected,
                    visualDensity: VisualDensity.compact,
                  ),
                RepoAvatar(
                  name: title.primary,
                  iconPath: repo.apkIconPath,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title.primary,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      if (title.hasSecondary)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(title.secondary!,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF94A3B8))),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // 管理按钮行：位于名称下方、检测等操作按钮上方
            Row(
              children: [
                const Spacer(),
                if (onClearDownloads != null)
                  IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      onPressed: onClearDownloads,
                      tooltip: '清空下载'),
                if (onMoreVersions != null || onRepoDetails != null)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: '更多',
                    onSelected: (key) {
                      if (key == 'versions') {
                        onMoreVersions?.call();
                      } else if (key == 'details') {
                        onRepoDetails?.call();
                      }
                    },
                    itemBuilder: (_) => [
                      if (onMoreVersions != null)
                        const PopupMenuItem(
                          value: 'versions',
                          child: Row(children: [
                            Icon(Icons.history, size: 18),
                            SizedBox(width: 8),
                            Text('更多版本'),
                          ]),
                        ),
                      if (onRepoDetails != null)
                        const PopupMenuItem(
                          value: 'details',
                          child: Row(children: [
                            Icon(Icons.info_outline, size: 18),
                            SizedBox(width: 8),
                            Text('仓库详情'),
                          ]),
                        ),
                    ],
                  ),
                IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: onEdit,
                    tooltip: '编辑'),
                IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    onPressed: onDelete,
                    tooltip: '删除'),
              ],
            ),
            if (repo.isApkRepo || (repo.downloadedVersion?.isNotEmpty ?? false))
              _kv('已下载版本', repo.downloadedVersion ?? '未下载'),
            _kv('已安装版本', repo.lastInstalledTag ?? '未安装'),
            _kv('仓库最新版本', latestTag ?? '未检测'),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(status!, style: TextStyle(color: _statusColor)),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ElevatedButton.icon(
                    onPressed: onCheck,
                    icon: const Icon(Icons.search),
                    label: const Text('检测')),
                if (onCancel != null)
                  ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C2D12),
                          foregroundColor: Colors.white),
                      onPressed: onCancel,
                      icon: const Icon(Icons.pause),
                      label: const Text('暂停'))
                else
                  ElevatedButton.icon(
                      onPressed: onUpdate,
                      icon: const Icon(Icons.download),
                      label: const Text('更新')),
                if (onRetryInstall != null)
                  ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF92400E),
                          foregroundColor: Colors.white),
                      onPressed: onRetryInstall,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试安装')),
                if (folderPath != null)
                  OutlinedButton.icon(
                      onPressed: onOpenFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('打开文件夹')),
                if (onLaunch != null)
                  OutlinedButton.icon(
                      onPressed: onLaunch,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('启动')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child:
                Text(label, style: const TextStyle(color: Color(0xFF94A3B8))),
          ),
          Expanded(
            child:
                Text(value, style: const TextStyle(color: Color(0xFFE2E8F0))),
          ),
        ],
      ),
    );
  }
}
