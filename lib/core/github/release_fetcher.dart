/// 统一 Release 获取入口：API 优先，失败回退直链；带内存缓存（TTL）。
library;

import 'api_client.dart';
import 'direct_link_fetcher.dart';
import 'release_model.dart';

class ReleaseFetcher {

  ReleaseFetcher({
    required this.api,
    required this.direct,
    this.preferApi = true,
    this.ttl = const Duration(minutes: 10),
  });
  final GitHubApiClient api;
  final DirectLinkFetcher direct;
  final bool preferApi;
  final Duration ttl;
  final Map<String, _CacheEntry> _cache = {};

  Future<Release> getLatest(String owner, String repo) async {
    final key = '$owner/$repo';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.time) < ttl) {
      return hit.release;
    }
    late Release release;
    try {
      if (preferApi) {
        release = await api.getLatestRelease(owner, repo);
      } else {
        throw Exception('forced direct');
      }
    } catch (e) {
      // API 失败（限流/无 Token/网络）时回退到直链
      release = await direct.fetchRelease(owner, repo);
    }
    _cache[key] = _CacheEntry(release, DateTime.now());
    return release;
  }

  /// 列出仓库的全部 release（含预发布；「更多版本」页用）。
  /// API 失败（限流/无 Token/网络）时回退直链——直链只能解析最新版，返回单条。
  Future<List<Release>> listReleases(String owner, String repo,
      {int perPage = 100}) async {
    try {
      if (preferApi) {
        return await api.listReleases(owner, repo, perPage: perPage);
      }
    } catch (_) {
      // 回退直链
    }
    return [await direct.fetchRelease(owner, repo)];
  }

  void clearCache() => _cache.clear();
}

class _CacheEntry {
  _CacheEntry(this.release, this.time);
  final Release release;
  final DateTime time;
}
