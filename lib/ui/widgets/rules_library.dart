import 'package:flutter/material.dart';
import '../../core/config/models.dart';
import '../../core/config/rule_presets.dart';

/// 规则库板块：只显示**当前宿主系统**的预设规则，
/// 点击某个预设即将其作为一条新规则加入（或覆盖选中的规则框）。
class RulesLibrary extends StatelessWidget {

  const RulesLibrary({super.key, required this.platform, required this.onPick});

  /// 当前宿主系统（只展示该系统的预设）
  final PlatformType platform;
  final void Function(AssetRule rule) onPick;

  @override
  Widget build(BuildContext context) {
    final presets = systemRulePresets[platform] ?? const <RulePreset>[];
    return Card(
      color: const Color(0xFF172033),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(platform), size: 18),
                const SizedBox(width: 6),
                Text('规则库 · ${_title(platform)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            const Text('先点击下方规则框选中，再点预设即可覆盖该框；未选中则新增一条',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: presets
                  .map((preset) => Tooltip(
                        message: preset.description,
                        child: ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(preset.name),
                          onPressed: () => onPick(preset.rule),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _title(PlatformType p) {
    switch (p) {
      case PlatformType.windows:
        return 'Windows 系统';
      case PlatformType.linux:
        return 'Linux 系统';
      case PlatformType.android:
        return 'Android 系统';
    }
  }

  IconData _icon(PlatformType p) {
    switch (p) {
      case PlatformType.windows:
        return Icons.desktop_windows_outlined;
      case PlatformType.linux:
        return Icons.terminal_outlined;
      case PlatformType.android:
        return Icons.android_outlined;
    }
  }
}
