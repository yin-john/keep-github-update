import 'package:flutter/material.dart';
import '../../core/config/models.dart';
import '../../core/config/rule_presets.dart';

/// 规则库板块：按 Windows / Linux / Android 三系统分组展示预设规则，
/// 点击某个预设即将其作为一条新规则加入。
class RulesLibrary extends StatelessWidget {

  const RulesLibrary({super.key, required this.onPick});
  final void Function(AssetRule rule) onPick;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF172033),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.library_books_outlined, size: 18),
                SizedBox(width: 6),
                Text('规则库（按系统）',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            const Text('先点击下方规则框选中，再点预设即可覆盖该框；未选中则新增一条',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            const SizedBox(height: 10),
            ...PlatformType.values.map(_buildGroup),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(PlatformType platform) {
    final presets = systemRulePresets[platform] ?? const <RulePreset>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon(platform), size: 16, color: const Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Text(_title(platform),
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFFCBD5E1))),
            ],
          ),
          const SizedBox(height: 4),
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
