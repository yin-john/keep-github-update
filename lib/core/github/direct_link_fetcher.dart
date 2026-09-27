/// 直链模式：不依赖 API Token，直接解析 GitHub releases 页面获取下载地址。
/// 适用于无 Token、镜像站、或 API 限流场景。
library;

import 'package:dio/dio.dart';
import 'release_model.dart';

class DirectLinkFetcher {

  DirectLinkFetcher({Dio? dio})
      : dio = dio ??
            Dio(BaseOptions(
              headers: {'User-Agent': 'grku'},
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ));
  final Dio dio;

  /// 获取指定 tag（或 latest）的资产列表，通过解析 expanded_assets 页面得到真实下载链接
  Future<Release> fetchRelease(String owner, String repo, {String? tag}) async {
    final tagPath = (tag == null || tag == 'latest') ? 'latest' : 'tag/$tag';
    final res = await dio.get(
      'https://github.com/$owner/$repo/releases/$tagPath',
      options: Options(
        followRedirects: true,
        validateStatus: (_) => true,
      ),
    );
    final resolvedTag = _extractTag(res) ?? tag ?? 'latest';
    final expandedUrl =
        'https://github.com/$owner/$repo/releases/expanded_assets/$resolvedTag';
    final html =
        (await dio.get(expandedUrl)).data as String;
    final assets = _parseAssets(html, owner, repo);
    return Release(
      tagName: resolvedTag,
      name: resolvedTag,
      prerelease: false,
      htmlUrl: 'https://github.com/$owner/$repo/releases/tag/$resolvedTag',
      assets: assets,
    );
  }

  String? _extractTag(Response res) {
    final location = res.redirects.isNotEmpty
        ? res.redirects.last.location.toString()
        : res.requestOptions.uri.toString();
    final m =
        RegExp(r'/releases/(?:tag|expanded_assets)/([^/?#]+)').firstMatch(location);
    return m?.group(1);
  }

  List<Asset> _parseAssets(String html, String owner, String repo) {
    final assets = <Asset>[];
    final re = RegExp(
      'href="(/$owner/$repo/releases/download/[^"]+)"',
      caseSensitive: false,
    );
    for (final m in re.allMatches(html)) {
      final path = m.group(1)!;
      final name = Uri.decodeComponent(path.split('/').last);
      assets.add(Asset(
        name: name,
        browserDownloadUrl: 'https://github.com$path',
        size: 0,
      ));
    }
    return assets;
  }
}
