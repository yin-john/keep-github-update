/// 从用户输入解析 GitHub 仓库引用。
///
/// 支持：
/// - 完整链接   https://github.com/owner/repo(.git)(/tree/main)
/// - SSH        git@github.com:owner/repo.git
/// - 无协议域名  github.com/owner/repo
/// - 简写       owner/repo
library;

/// 解析出的仓库归属
class RepoRef {
  const RepoRef(this.owner, this.repo);
  final String owner;
  final String repo;

  @override
  String toString() => '$owner/$repo';
}

final RegExp _schemeRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
final RegExp _sshRe = RegExp(r'^[^@\s]+@[^:\s]+:(.+)$');
final RegExp _domainRe = RegExp(r'^[^/\s]+\.[^/\s]+/(.+)$');
final RegExp _dotGitRe = RegExp(r'\.git$', caseSensitive: false);

RepoRef? parseGitHubRef(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return null;

  // SSH: git@github.com:owner/repo.git
  final ssh = _sshRe.firstMatch(input);
  if (ssh != null) return _fromPath(ssh.group(1)!);

  // 带协议的完整 URL
  if (_schemeRe.hasMatch(input)) {
    final uri = Uri.tryParse(input);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return _fromSegments(uri.pathSegments);
    }
  }

  // 无协议但含域名: github.com/owner/repo
  final domain = _domainRe.firstMatch(input);
  if (domain != null) return _fromPath(domain.group(1)!);

  // owner/repo 简写
  return _fromPath(input);
}

RepoRef? _fromPath(String path) {
  var p = path.trim();
  p = p.split('?').first.split('#').first;
  return _fromSegments(p.split('/'));
}

RepoRef? _fromSegments(Iterable<String> segments) {
  final segs = segments
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map((e) => e.replaceAll(_dotGitRe, ''))
      .where((e) => e.isNotEmpty)
      .toList();
  if (segs.length < 2) return null;
  return RepoRef(segs[0], segs[1]);
}
