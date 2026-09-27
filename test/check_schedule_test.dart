import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/scheduler/check_schedule.dart';

void main() {
  group('检测间隔（全局 + 仓库级覆盖）', () {
    test('仓库级优先，未设置时用全局', () {
      expect(effectiveCheckInterval(30, 360), 30);
      expect(effectiveCheckInterval(null, 360), 360);
      expect(effectiveCheckInterval(0, 360), 0);
    });

    test('间隔 > 0 才算开启自动检测', () {
      expect(autoCheckEnabled(0), isFalse);
      expect(autoCheckEnabled(15), isTrue);
    });
  });

  group('是否到期', () {
    final now = DateTime(2026, 1, 1, 12, 0);

    test('从未检测过 → 到期', () {
      expect(
        isCheckDue(lastCheckedAt: null, intervalMinutes: 60, now: now),
        isTrue,
      );
    });

    test('未满间隔 → 未到期', () {
      expect(
        isCheckDue(
            lastCheckedAt: now.subtract(const Duration(minutes: 30)),
            intervalMinutes: 60,
            now: now),
        isFalse,
      );
    });

    test('已满间隔 → 到期', () {
      expect(
        isCheckDue(
            lastCheckedAt: now.subtract(const Duration(minutes: 60)),
            intervalMinutes: 60,
            now: now),
        isTrue,
      );
    });

    test('关闭（0 或负数）时永不到期', () {
      expect(
        isCheckDue(lastCheckedAt: null, intervalMinutes: 0, now: now),
        isFalse,
      );
      expect(
        isCheckDue(lastCheckedAt: null, intervalMinutes: -1, now: now),
        isFalse,
      );
    });

    test('下次检测时间', () {
      final next = nextCheckTime(
          lastCheckedAt: now, intervalMinutes: 90);
      expect(next, now.add(const Duration(minutes: 90)));
      expect(nextCheckTime(lastCheckedAt: now, intervalMinutes: 0), isNull);
      expect(nextCheckTime(lastCheckedAt: null, intervalMinutes: 60), isNull);
    });
  });

  group('时间戳与文案', () {
    test('时间戳往返', () {
      final t = DateTime(2026, 1, 2, 3, 4, 5);
      expect(parseTimestamp(formatTimestamp(t)), t);
      expect(parseTimestamp(null), isNull);
      expect(parseTimestamp('  '), isNull);
      expect(parseTimestamp('not-a-date'), isNull);
    });

    test('间隔描述', () {
      expect(describeInterval(0), '关闭');
      expect(describeInterval(30), '30 分钟');
      expect(describeInterval(60), '1 小时');
      expect(describeInterval(360), '6 小时');
      expect(describeInterval(720), '12 小时');
      expect(describeInterval(1440), '1 天');
      expect(describeInterval(2880), '2 天');
      expect(describeInterval(90), '90 分钟');
    });

    test('剩余时间描述', () {
      final now = DateTime(2026, 1, 1, 12, 0);
      expect(describeTimeUntil(null, now), '未安排');
      expect(describeTimeUntil(now.add(const Duration(seconds: 20)), now),
          '不到 1 分钟');
      expect(describeTimeUntil(now.add(const Duration(minutes: 30)), now),
          '30 分钟后');
      expect(describeTimeUntil(now.add(const Duration(hours: 5)), now),
          '5 小时后');
      expect(describeTimeUntil(now.add(const Duration(days: 2)), now),
          '2 天后');
      expect(describeTimeUntil(now.subtract(const Duration(minutes: 1)), now),
          '即将检测');
    });

    test('间隔预设包含「关闭」且递增', () {
      expect(intervalPresets.first, 0);
      for (var i = 1; i < intervalPresets.length; i++) {
        expect(intervalPresets[i] > intervalPresets[i - 1], isTrue);
      }
    });
  });
}
