import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/core/download/download_manager.dart';
import 'package:github_releases_keep_update/core/github/api_client.dart';
import 'package:github_releases_keep_update/core/github/direct_link_fetcher.dart';
import 'package:github_releases_keep_update/core/github/release_fetcher.dart';
import 'package:github_releases_keep_update/core/github/release_model.dart';
import 'package:github_releases_keep_update/core/matcher/asset_matcher.dart';
import 'package:github_releases_keep_update/core/mirror/mirror_resolver.dart';
import 'package:github_releases_keep_update/core/updater/update_service.dart';
import 'package:github_releases_keep_update/core/updater/updater.dart';
import 'package:github_releases_keep_update/core/version/installed_version.dart';

import 'support/test_server.dart';

class _FakeApi extends GitHubApiClient {
  _FakeApi(this.release) : super(dio: Dio());
  final Release release;
  @override
  Future<Release> getLatestRelease(String owner, String repo) async => release;
}

class _FakeDirect extends DirectLinkFetcher {
  _FakeDirect() : super(dio: Dio());
  @override
  Future<Release> fetchRelease(String owner, String repo, {String? tag}) async {
    throw StateError('direct 不应被调用');
  }
}

class _RecordingUpdater implements Updater {
  int applied = 0;
  @override
  bool isApplicable(PlatformType p, UpdateStrategy s) => true;
  @override
  Future<void> apply({
    required Asset asset,
    required String localPath,
    required RepoConfig repo,
    required AssetRule rule,
  }) async {
    applied++;
  }
}

/// 前 [failTimes] 次安装失败，之后成功（用于测试「重试安装」）
class _FlakyUpdater implements Updater {
  _FlakyUpdater({this.failTimes = 1});
  int attempts = 0;
  final int failTimes;

  @override
  bool isApplicable(PlatformType p, UpdateStrategy s) => true;

  @override
  Future<void> apply({
    required Asset asset,
    required String localPath,
    required RepoConfig repo,
    required AssetRule rule,
  }) async {
    attempts++;
    if (attempts <= failTimes) {
      throw Exception('模拟安装失败（第 $attempts 次）');
    }
  }
}

const _windowsZipRule = AssetRule(
  platform: PlatformType.windows,
  strategy: UpdateStrategy.portable,
  nameRegex: r'.*\.zip$',
);

final _managers = <DownloadManager>[];

UpdateService _serviceFor(Release rel, Updater updater, {int threads = 1}) {
  final dl = DownloadManager(threads: threads);
  _managers.add(dl);
  return UpdateService(
    fetcher: ReleaseFetcher(api: _FakeApi(rel), direct: _FakeDirect()),
    mirror: const MirrorResolver([]),
    matcher: AssetMatcher(),
    downloader: dl,
    updaters: [updater],
    currentPlatform: PlatformType.windows,
  );
}

Release _releaseFor(String tag, String assetUrl) => Release(
      tagName: tag,
      name: tag,
      prerelease: false,
      htmlUrl: '',
      assets: [Asset(name: 'app.zip', browserDownloadUrl: assetUrl, size: 1)],
    );

void main() {
  final data = List<int>.generate(64 * 1024, (i) => i % 251);

  late Directory tmp;
  // flutter_test 默认拦截真实网络，这里需要访问本地 HTTP 服务器
  setUpAll(() => HttpOverrides.global = null);
  setUp(() => tmp = Directory.systemTemp.createTempSync('grku_up_'));
  tearDown(() {
    for (final m in _managers) {
      m.dio.close(force: true);
    }
    _managers.clear();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('更新全流程：检测 → 下载 → 应用 → 写入版本文件', () async {
    final server = await TestServer.start(data);
    final updater = _RecordingUpdater();
    final svc = _serviceFor(_releaseFor('v1.0.0', server.url('/file')), updater);
    final installDir = Directory('${tmp.path}/install')
      ..createSync(recursive: true);
    final repo = RepoConfig(
      id: 'o/r',
      owner: 'o',
      repo: 'r',
      installDir: installDir.path,
      assetRules: const [_windowsZipRule],
    );

    final check = await svc.check(repo);
    expect(check.hasUpdate, isTrue);

    final file = await svc.update(check, downloadDir: '${tmp.path}/dl');
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), equals(data));
    expect(updater.applied, 1);

    final vf = File('${installDir.path}/$versionFileName');
    expect(vf.existsSync(), isTrue);
    expect(vf.readAsStringSync(), contains('version: v1.0.0'));

    await server.close();
  });

  test('多线程更新流程同样可用', () async {
    final server = await TestServer.start(data);
    final updater = _RecordingUpdater();
    final svc = _serviceFor(_releaseFor('v2', server.url('/file')), updater,
        threads: 4);
    final repo = RepoConfig(
      id: 'o/r',
      owner: 'o',
      repo: 'r',
      installDir: tmp.path,
      assetRules: const [_windowsZipRule],
    );
    final check = await svc.check(repo);
    final file = await svc.update(check, downloadDir: '${tmp.path}/dl');
    expect(file.readAsBytesSync(), equals(data));
    expect(updater.applied, 1);
    await server.close();
  });

  test('无匹配资产：不是已最新，且更新报错', () async {
    final updater = _RecordingUpdater();
    const rel = Release(
      tagName: 'v1',
      name: 'v1',
      prerelease: false,
      htmlUrl: '',
      assets: const [
        Asset(name: 'app.apk', browserDownloadUrl: 'http://x/app.apk', size: 1),
      ],
    );
    final svc = _serviceFor(rel, updater);
    const repo = RepoConfig(
      id: 'o/r',
      owner: 'o',
      repo: 'r',
      assetRules: const [_windowsZipRule],
    );
    final check = await svc.check(repo);
    expect(check.match, isNull);
    expect(check.hasUpdate, isFalse);
    expect(describeCheck(check), '未找到匹配的资产');
    await expectLater(svc.update(check), throwsA(isA<Exception>()));
    expect(updater.applied, 0);
  });

  test('未安装可更新；已装同版本为已最新', () async {
    final svc = _serviceFor(_releaseFor('v1', 'http://x/app.zip'), _RecordingUpdater());
    final notInstalled = await svc.check(const RepoConfig(
        id: 'o/r', owner: 'o', repo: 'r', assetRules: [_windowsZipRule]));
    expect(notInstalled.hasUpdate, isTrue);
    expect(describeCheck(notInstalled), contains('未安装'));

    final same = await svc.check(const RepoConfig(
        id: 'o/r',
        owner: 'o',
        repo: 'r',
        lastInstalledTag: 'v1',
        assetRules: [_windowsZipRule]));
    expect(same.hasUpdate, isFalse);
    expect(describeCheck(same), contains('已是最新'));
  });

  test('更新可中断', () async {
    final slow = List<int>.generate(256 * 1024, (i) => i % 251);
    final server = await TestServer.start(slow);
    final updater = _RecordingUpdater();
    final svc = _serviceFor(_releaseFor('v1', server.url('/slow')), updater);
    final repo = RepoConfig(
      id: 'o/r',
      owner: 'o',
      repo: 'r',
      installDir: tmp.path,
      assetRules: const [_windowsZipRule],
    );
    final check = await svc.check(repo);
    final token = CancelToken();
    final fut = svc.update(check,
        downloadDir: '${tmp.path}/dl', cancelToken: token);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    token.cancel();
    await expectLater(fut, throwsA(isA<DownloadCancelled>()));
    expect(updater.applied, 0);
    await server.close();
  });

  test('下载成功但安装失败 → 抛 InstallFailedException 且文件保留', () async {
    final server = await TestServer.start(data);
    final updater = _FlakyUpdater(failTimes: 99);
    final svc =
        _serviceFor(_releaseFor('v1.0.0', server.url('/file')), updater);
    const repo = RepoConfig(
        id: 'o/r', owner: 'o', repo: 'r', assetRules: const [_windowsZipRule]);
    final dlDir = '${tmp.path}/dl';

    final check = await svc.check(repo);
    await expectLater(
      svc.update(check, downloadDir: dlDir),
      throwsA(isA<InstallFailedException>()),
    );

    // 已下载的文件仍在，可直接重试安装
    final file = await svc.lastDownloadedFile(repo, downloadDir: dlDir);
    expect(file, isNotNull);
    expect(file!.existsSync(), isTrue);
    await server.close();
  });

  test('重试安装复用已下载文件，不重新下载', () async {
    final server = await TestServer.start(data);
    final updater = _FlakyUpdater(failTimes: 1);
    final svc =
        _serviceFor(_releaseFor('v1.0.0', server.url('/file')), updater);
    final installDir = Directory('${tmp.path}/install')
      ..createSync(recursive: true);
    final repo = RepoConfig(
      id: 'o/r',
      owner: 'o',
      repo: 'r',
      installDir: installDir.path,
      assetRules: const [_windowsZipRule],
    );
    final dlDir = '${tmp.path}/dl';

    final check = await svc.check(repo);
    await expectLater(
      svc.update(check, downloadDir: dlDir),
      throwsA(isA<InstallFailedException>()),
    );
    expect(updater.attempts, 1);

    final file = await svc.lastDownloadedFile(repo, downloadDir: dlDir);
    expect(file, isNotNull);
    final applied = await svc.applyDownloaded(check, file!);

    expect(applied.path, file.path); // 用的还是同一个文件
    expect(updater.attempts, 2);
    // 重试成功后写入版本记录
    expect(File('${installDir.path}/$versionFileName').existsSync(), isTrue);
    await server.close();
  });

  test('lastDownloadedFile 跳过分片与版本记录文件', () async {
    final svc = _serviceFor(_releaseFor('v1', 'http://x/app.zip'), _RecordingUpdater());
    const repo = RepoConfig(
        id: 'o/r', owner: 'o', repo: 'r', assetRules: const [_windowsZipRule]);
    final dlDir = Directory('${tmp.path}/dl/o@r')..createSync(recursive: true);
    File('${dlDir.path}/app.zip.part').writeAsStringSync('part');
    File('${dlDir.path}/app.zip.resume').writeAsStringSync('resume');
    File('${dlDir.path}/$versionFileName').writeAsStringSync('repo: o/r');
    File('${dlDir.path}/app.zip').writeAsStringSync('real');

    final file = await svc.lastDownloadedFile(repo, downloadDir: '${tmp.path}/dl');
    expect(file, isNotNull);
    expect(file!.path.endsWith('app.zip'), isTrue);
  });
}
