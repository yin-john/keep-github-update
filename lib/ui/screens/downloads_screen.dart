import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';

/// 「下载」选项卡：查看所有进行中/最近完成的下载任务，可暂停
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadsProvider);
    final hasFinished = tasks.any((t) => !t.active);
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载'),
        actions: [
          TextButton.icon(
            onPressed: hasFinished
                ? () => ref.read(downloadsProvider.notifier).clearFinished()
                : null,
            icon: const Icon(Icons.clear_all, size: 18),
            label: const Text('清除已完成'),
          ),
        ],
      ),
      body: tasks.isEmpty
          ? const Center(
              child: Text('暂无下载任务',
                  style: TextStyle(color: Color(0xFF94A3B8))))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (_, i) {
                final t = tasks[i];
                final pct = t.progress == null
                    ? ''
                    : ' ${(t.progress! * 100).toStringAsFixed(0)}%';
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(t.repo,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (t.active)
                              OutlinedButton.icon(
                                onPressed: () => ref
                                    .read(downloadsProvider.notifier)
                                    .cancel(t.repo),
                                icon: const Icon(Icons.pause, size: 16),
                                label: const Text('暂停'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${t.status}$pct'
                          '${t.active ? ' · ${_fmtSpeed(t.speed)}' : ''}',
                          style:
                              const TextStyle(color: Color(0xFFCBD5E1)),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                            value: t.active ? t.progress : (t.progress ?? 0),
                            minHeight: 6),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
