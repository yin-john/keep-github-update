import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/app_paths.dart';

void main() {
  test('应用数据目录名与应用同名', () {
    expect(appDirName, 'github_releases_keep_update');
    expect(appDataDir().endsWith(appDirName), isTrue);
  });

  test('默认下载目录位于应用数据目录下', () {
    final dir = defaultDownloadDir();
    expect(dir.contains(appDirName), isTrue);
    expect(dir.endsWith('downloads'), isTrue);
  });

  test('仓库下载目录为 <基准>/<owner>@<repo>', () {
    final dir = repoDownloadDir('o', 'r');
    expect(dir.contains(appDirName), isTrue);
    expect(dir.endsWith('o@r'), isTrue);
  });
}
