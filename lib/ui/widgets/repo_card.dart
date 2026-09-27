import 'package:flutter/material.dart';
import '../../core/config/models.dart';

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

  Color get _statusColor {
    if (hasUpdate == true) return const Color(0xFF22C55E); // 可更新：绿
    if (hasUpdate == false) return const Color(0xFFF59E0B); // 已最新：琥珀
    return const Color(0xFF94A3B8); // 未知/失败：灰
  }

  @override
  Widget build(BuildContext context) {
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
                Expanded(
                  child: Text(repo.fullName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (onClearDownloads != null)
                  IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      onPressed: onClearDownloads,
                      tooltip: '清空下载'),
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
            _kv('已装版本', repo.lastInstalledTag ?? '未安装'),
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
