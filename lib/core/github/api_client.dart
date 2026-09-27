/// GitHub REST API 客户端（支持注入 Personal Access Token）
library;

import 'package:dio/dio.dart';
import 'release_model.dart';

class GitHubApiClient {

  GitHubApiClient({Dio? dio, this.token})
      : dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.github.com',
              headers: const {'Accept': 'application/vnd.github+json'},
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            )) {
    if (token != null && token!.isNotEmpty) {
      this.dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }
  final Dio dio;
  final String? token;

  /// 获取最新（非预发布）release
  Future<Release> getLatestRelease(String owner, String repo) async {
    final res = await dio.get('/repos/$owner/$repo/releases/latest');
    return Release.fromJson(res.data as Map<String, dynamic>);
  }

  /// 列出最近若干 release（含预发布），用于 tag 过滤
  Future<List<Release>> listReleases(String owner, String repo,
      {int perPage = 10}) async {
    final res = await dio.get('/repos/$owner/$repo/releases',
        queryParameters: {'per_page': perPage});
    return (res.data as List)
        .map((e) => Release.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
