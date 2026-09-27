import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:github_releases_keep_update/core/github/api_client.dart';
import 'package:github_releases_keep_update/core/github/direct_link_fetcher.dart';
import 'package:github_releases_keep_update/core/github/release_fetcher.dart';
import 'package:github_releases_keep_update/core/github/release_model.dart';

/// 用假实现替代 API 客户端，验证获取层优先 API 并走缓存
class _FakeApi extends GitHubApiClient {
  _FakeApi() : super(dio: Dio());
  int calls = 0;
  @override
  Future<Release> getLatestRelease(String owner, String repo) async {
    calls++;
    return const Release(
      tagName: 'v2.0.0',
      name: 'v2.0.0',
      prerelease: false,
      htmlUrl: '',
      assets: [
        Asset(
            name: 'a.zip',
            browserDownloadUrl: 'https://github.com/o/r/releases/download/v2/a.zip',
            size: 1),
      ],
    );
  }
}

class _FakeDirect extends DirectLinkFetcher {
  _FakeDirect() : super(dio: Dio());
  int calls = 0;
  @override
  Future<Release> fetchRelease(String owner, String repo, {String? tag}) async {
    calls++;
    return const Release(
        tagName: 'v1.0.0',
        name: 'v1.0.0',
        prerelease: false,
        htmlUrl: '',
        assets: []);
  }
}

void main() {
  test('优先使用 API 且命中缓存不再请求', () async {
    final api = _FakeApi();
    final direct = _FakeDirect();
    final fetcher = ReleaseFetcher(api: api, direct: direct);
    final r1 = await fetcher.getLatest('o', 'r');
    final r2 = await fetcher.getLatest('o', 'r');
    expect(r1.tagName, 'v2.0.0');
    expect(r2.tagName, 'v2.0.0'); // 第二次返回同样的缓存结果
    expect(api.calls, 1); // 第二次命中缓存
    expect(direct.calls, 0);
  });

  test('API 失败时回退直链', () async {
    final direct = _FakeDirect();
    final failingApi = _FailingApi();
    final fetcher = ReleaseFetcher(api: failingApi, direct: direct);
    final r = await fetcher.getLatest('o', 'r');
    expect(r.tagName, 'v1.0.0');
    expect(direct.calls, 1);
  });
}

class _FailingApi extends GitHubApiClient {
  _FailingApi() : super(dio: Dio());
  @override
  Future<Release> getLatestRelease(String owner, String repo) async {
    throw Exception('rate limited');
  }
}
