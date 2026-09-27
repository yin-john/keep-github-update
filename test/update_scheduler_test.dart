import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/core/scheduler/update_scheduler.dart';

RepoConfig _repo(String name, {int? interval, DateTime? last}) => RepoConfig(
      id: 'o/$name',
      owner: 'o',
      repo: name,
      assetRules: const [
        AssetRule(
            platform: PlatformType.windows,
            strategy: UpdateStrategy.portable,
            nameRegex: '.*'),
      ],
      checkIntervalMinutes: interval,
      lastCheckedAt: last?.toIso8601String(),
    );

void main() {
  final now = DateTime(2026, 1, 1, 12, 0);

  UpdateScheduler build({
    required List<RepoConfig> repos,
    required int global,
    required List<String> fired,
  }) {
    return UpdateScheduler(
      repos: () => repos,
      globalInterval: () => global,
      onDue: (r) async => fired.add(r.fullName),
      clock: () => now,
    );
  }

  test('全局关闭时不检测任何仓库', () async {
    final fired = <String>[];
    final s = build(
      repos: [_repo('a'), _repo('b')],
      global: 0,
      fired: fired,
    );
    expect(await s.tickOnce(), 0);
    expect(fired, isEmpty);
  });

  test('从未检测过的仓库到期，已被检测且未满间隔的跳过', () async {
    final fired = <String>[];
    final s = build(
      repos: [
        _repo('fresh'),
        _repo('recent', last: now.subtract(const Duration(minutes: 10))),
        _repo('old', last: now.subtract(const Duration(hours: 8))),
      ],
      global: 360,
      fired: fired,
    );
    expect(await s.tickOnce(), 2);
    expect(fired, ['o/fresh', 'o/old']);
  });

  test('仓库级间隔覆盖全局间隔', () async {
    final fired = <String>[];
    final s = build(
      repos: [
        _repo('fast', interval: 15, last: now.subtract(const Duration(minutes: 20))),
        _repo('slow', interval: 1440, last: now.subtract(const Duration(minutes: 20))),
        _repo('off', interval: 0),
      ],
      global: 60,
      fired: fired,
    );
    expect(await s.tickOnce(), 1);
    expect(fired, ['o/fast']);
  });

  test('单个仓库失败不影响其它仓库', () async {
    final fired = <String>[];
    var first = true;
    final s = UpdateScheduler(
      repos: () => [_repo('boom'), _repo('ok')],
      globalInterval: () => 60,
      onDue: (r) async {
        if (first) {
          first = false;
          throw Exception('网络错误');
        }
        fired.add(r.fullName);
      },
      clock: () => now,
    );
    expect(await s.tickOnce(), 2);
    expect(fired, ['o/ok']);
  });

  test('tickOnce 计数与下次检测时间', () async {
    final fired = <String>[];
    final s = build(
      repos: [
        _repo('a', interval: 60, last: now),
        _repo('b', interval: 120, last: now),
      ],
      global: 60,
      fired: fired,
    );
    expect(s.tickCount, 0);
    await s.tickOnce();
    await s.tickOnce();
    expect(s.tickCount, 2);
    expect(fired, isEmpty); // 都未到间隔
    expect(s.nextCheckAt(), now.add(const Duration(minutes: 60)));
  });

  test('当前生效间隔查询', () {
    final s = build(repos: const [], global: 360, fired: []);
    expect(s.intervalFor(_repo('x')), 360);
    expect(s.intervalFor(_repo('x', interval: 30)), 30);
  });

  test('start / stop 幂等且状态正确', () {
    final s = build(repos: [_repo('a')], global: 60, fired: [])
      ..stop();
    expect(s.running, isFalse);
    s.start();
    expect(s.running, isTrue);
    s.start(); // 重复启动安全
    expect(s.running, isTrue);
    s.stop();
    expect(s.running, isFalse);
    s.stop();
    expect(s.running, isFalse);
  });
}
