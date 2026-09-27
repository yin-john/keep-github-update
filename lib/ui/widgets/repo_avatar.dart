import 'dart:io';

import 'package:flutter/material.dart';

/// 仓库图标。
///
/// - Android：可显示从下载到的 APK 中提取的图标（PNG 文件）；
/// - 其它平台 / 尚未获取到图标：退化为「名称首字」圆形头像，
///   避免在不支持提取图标的平台上显示裂图（符合当前环境）。
class RepoAvatar extends StatelessWidget {
  const RepoAvatar({
    super.key,
    required this.name,
    this.iconPath,
    this.size = 40,
  });

  final String name;
  final String? iconPath;
  final double size;

  bool get _iconUsable {
    final p = iconPath;
    if (p == null || p.isEmpty) return false;
    try {
      return File(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_iconUsable) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.file(
          File(iconPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colorFor(name),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 由名称推导稳定颜色，保证同一仓库每次显示一致
  Color _colorFor(String seed) {
    const palette = [
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFFEF4444),
      Color(0xFF06B6D4),
    ];
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
}
