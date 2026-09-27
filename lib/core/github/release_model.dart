/// GitHub Release / Asset 数据模型
library;

class Asset {

  const Asset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
    this.contentType,
  });

  factory Asset.fromJson(Map<String, dynamic> j) => Asset(
        name: j['name'] as String,
        browserDownloadUrl: j['browser_download_url'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        contentType: j['content_type'] as String?,
      );
  final String name;
  final String browserDownloadUrl;
  final int size;
  final String? contentType;
}

class Release {

  const Release({
    required this.tagName,
    required this.name,
    this.publishedAt,
    required this.prerelease,
    required this.htmlUrl,
    required this.assets,
  });

  factory Release.fromJson(Map<String, dynamic> j) => Release(
        tagName: j['tag_name'] as String,
        name: (j['name'] as String?) ?? (j['tag_name'] as String),
        publishedAt: j['published_at'] != null
            ? DateTime.tryParse(j['published_at'] as String)
            : null,
        prerelease: j['prerelease'] as bool? ?? false,
        htmlUrl: (j['html_url'] as String?) ?? '',
        assets: (j['assets'] as List? ?? [])
            .map((e) => Asset.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
  final String tagName;
  final String name;
  final DateTime? publishedAt;
  final bool prerelease;
  final String htmlUrl;
  final List<Asset> assets;
}
