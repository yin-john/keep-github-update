/// 自动检测间隔调度（纯逻辑，便于单元测试）。
///
/// - 全局设置 [AppConfig.checkIntervalMinutes] 决定默认间隔；
/// - 仓库可用 [RepoConfig.checkIntervalMinutes] 覆盖；
/// - 间隔为 0 表示「关闭自动检测」；
/// - 上次检测时间记录在 [RepoConfig.lastCheckedAt]。
library;

/// 常用间隔预设（分钟）：0 = 关闭
const List<int> intervalPresets = [0, 15, 30, 60, 180, 360, 720, 1440];

/// 生效的检测间隔（分钟）：仓库级优先，其次全局
int effectiveCheckInterval(int? repoInterval, int globalInterval) =>
    repoInterval ?? globalInterval;

/// 自动检测是否已开启（间隔 > 0）
bool autoCheckEnabled(int intervalMinutes) => intervalMinutes > 0;

/// 该仓库此刻是否应当检测
///
/// [lastCheckedAt] 为空（从未检测）且自动检测开启时视为到期。
bool isCheckDue({
  required DateTime? lastCheckedAt,
  required int intervalMinutes,
  required DateTime now,
}) {
  if (!autoCheckEnabled(intervalMinutes)) return false;
  final last = lastCheckedAt;
  if (last == null) return true;
  return !now.isBefore(last.add(Duration(minutes: intervalMinutes)));
}

/// 下次检测时间；关闭自动检测或从未检测过时返回 null
DateTime? nextCheckTime({
  required DateTime? lastCheckedAt,
  required int intervalMinutes,
}) {
  if (!autoCheckEnabled(intervalMinutes)) return null;
  final last = lastCheckedAt;
  if (last == null) return null;
  return last.add(Duration(minutes: intervalMinutes));
}

/// 解析时间戳（ISO8601）；非法或为空返回 null
DateTime? parseTimestamp(String? iso) {
  final s = iso?.trim() ?? '';
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// 生成用于持久化的时间戳
String formatTimestamp(DateTime t) => t.toIso8601String();

/// 人类可读的间隔描述
String describeInterval(int minutes) {
  if (minutes <= 0) return '关闭';
  if (minutes < 60) return '$minutes 分钟';
  if (minutes % 1440 == 0) return '${minutes ~/ 1440} 天';
  if (minutes % 60 == 0) {
    final h = minutes ~/ 60;
    return h >= 24 ? '${(minutes / 1440).toStringAsFixed(1)} 天' : '$h 小时';
  }
  return '$minutes 分钟';
}

/// 到下次检测的剩余时间描述（用于「下载/设置」页展示后台状态）
String describeTimeUntil(DateTime? next, DateTime now) {
  if (next == null) return '未安排';
  final diff = next.difference(now);
  if (diff.isNegative) return '即将检测';
  if (diff.inMinutes < 1) return '不到 1 分钟';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟后';
  if (diff.inHours < 24) return '${diff.inHours} 小时后';
  return '${diff.inDays} 天后';
}
