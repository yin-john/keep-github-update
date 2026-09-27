import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/github/repo_ref.dart';

void main() {
  group('parseGitHubRef', () {
    test('完整链接', () {
      expect(parseGitHubRef('https://github.com/microsoft/vscode')?.toString(),
          'microsoft/vscode');
      expect(
          parseGitHubRef('https://github.com/microsoft/vscode.git')?.toString(),
          'microsoft/vscode');
    });

    test('带子路径与查询参数', () {
      expect(
          parseGitHubRef('https://github.com/microsoft/vscode/tree/main')
              ?.toString(),
          'microsoft/vscode');
      expect(
          parseGitHubRef('https://github.com/owner/repo?tab=readme')?.toString(),
          'owner/repo');
    });

    test('SSH 形式', () {
      expect(parseGitHubRef('git@github.com:microsoft/vscode.git')?.toString(),
          'microsoft/vscode');
    });

    test('无协议域名与简写', () {
      expect(parseGitHubRef('github.com/microsoft/vscode')?.toString(),
          'microsoft/vscode');
      expect(parseGitHubRef('microsoft/vscode')?.toString(), 'microsoft/vscode');
      expect(parseGitHubRef('  microsoft/vscode/  ')?.toString(),
          'microsoft/vscode');
    });

    test('无效输入', () {
      expect(parseGitHubRef(''), isNull);
      expect(parseGitHubRef('   '), isNull);
      expect(parseGitHubRef('nonsense'), isNull);
    });
  });
}
