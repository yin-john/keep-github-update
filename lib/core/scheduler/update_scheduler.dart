/// 自动检测调度器：按「全局间隔 + 仓库级覆盖」周期性地触发检测。
///
/// 时间来源与副作用都通过回调注入，便于单元测试。
library;

import 'dart:async';
import '../config/models.dart';
import 'check_schedule.dart';

class UpdateScheduler {
  UpdateScheduler({
    required this.repos,
    required this.globalInterval,
    required this.onDue,
    this.onTick,
    this.tick = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 当前仓库列表
  final List<RepoConfig> Function() repos;

  /// 全局检测间隔（分钟，0 = 关闭自动检测）
  final int Function() globalInterval;

  /// 某个仓库到期时执行（通常是发起一次静默检测）
  final Future<void> Function(RepoConfig repo) onDue;

  /// 每次唤醒后调用（可用于刷新常驻通知中的「下次检测」时间）
  final Future<void> Function()? onTick;

  /// 检查周期（默认每分钟唤醒一次，判断哪些仓库到期）
  final Duration tick;
  final DateTime Function() _clock;

  Timer? _timer;
  int tickCount = 0;

  bool get running => _timer != null;

  /// 该仓库实际生效的间隔（分钟）
  int intervalFor(RepoConfig r) =>
      effectiveCheckInterval(r.checkIntervalMinutes, globalInterval());

  /// 启动周期检测（重复调用安全）
  void start() {
    _timer ??= Timer.periodic(tick, (_) async {
      await tickOnce();
      try {
        await onTick?.call();
      } catch (_) {
        // 通知刷新失败不影响检测
      }
    });
  }

  /// 停止周期检测
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 立即执行一轮：对已到期的仓库调用 [onDue]，返回触发数量
  Future<int> tickOnce() async {
    tickCount++;
    final g = globalInterval();
    if (!autoCheckEnabled(g)) return 0; // 全局关闭时不检测任何仓库
    final now = _clock();
    var fired = 0;
    for (final r in repos()) {
      final iv = effectiveCheckInterval(r.checkIntervalMinutes, g);
      if (!isCheckDue(
        lastCheckedAt: parseTimestamp(r.lastCheckedAt),
        intervalMinutes: iv,
        now: now,
      )) {
        continue;
      }
      fired++;
      try {
        await onDue(r);
      } catch (_) {
        // 单个仓库失败不影响其它仓库
      }
    }
    return fired;
  }

  /// 全部仓库中「下一次检测」最早的时间（用于展示）
  DateTime? nextCheckAt() {
    final g = globalInterval();
    if (!autoCheckEnabled(g)) return null;
    DateTime? earliest;
    for (final r in repos()) {
      final iv = effectiveCheckInterval(r.checkIntervalMinutes, g);
      final t = nextCheckTime(
        lastCheckedAt: parseTimestamp(r.lastCheckedAt),
        intervalMinutes: iv,
      );
      if (t != null && (earliest == null || t.isBefore(earliest))) earliest = t;
    }
    return earliest;
  }
}
