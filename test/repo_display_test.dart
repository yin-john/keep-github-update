import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/repo_display.dart';

void main() {
  group('仓库标题（自定义名称 / 自动获取名称 / 作者仓库名）', () {
    test('无自定义名称、无自动名称：只显示作者/仓库名', () {
      final t = resolveRepoTitle(fullName: 'yt-dlp/yt-dlp');
      expect(t.primary, 'yt-dlp/yt-dlp');
      expect(t.secondary, isNull);
      expect(t.hasSecondary, isFalse);
    });

    test('有自定义名称：主标题为自定义名称，副标题为作者/仓库名', () {
      final t = resolveRepoTitle(
          fullName: 'yt-dlp/yt-dlp', displayName: '视频下载器');
      expect(t.primary, '视频下载器');
      expect(t.secondary, 'yt-dlp/yt-dlp');
    });

    test('无自定义名称但获取到软件名称：同样显示两行', () {
      final t = resolveRepoTitle(
          fullName: 'foo/bar', apkLabel: '示例应用');
      expect(t.primary, '示例应用');
      expect(t.secondary, 'foo/bar');
    });

    test('自定义名称优先于自动获取的名称', () {
      final t = resolveRepoTitle(
          fullName: 'foo/bar', displayName: '我的名称', apkLabel: 'APK 名称');
      expect(t.primary, '我的名称');
      expect(t.secondary, 'foo/bar');
    });

    test('名称为空白时视为没有名称', () {
      expect(resolveRepoTitle(fullName: 'a/b', displayName: '   ').primary, 'a/b');
      expect(resolveRepoTitle(fullName: 'a/b', apkLabel: '').primary, 'a/b');
    });

    test('自定义名称与作者/仓库名相同时不重复显示', () {
      final t = resolveRepoTitle(fullName: 'a/b', displayName: 'a/b');
      expect(t.primary, 'a/b');
      expect(t.hasSecondary, isFalse);
    });

    test('名称两侧空白会被裁掉', () {
      final t = resolveRepoTitle(fullName: 'a/b', displayName: '  工具  ');
      expect(t.primary, '工具');
      expect(t.secondary, 'a/b');
    });

    test('hasCustomName 判定', () {
      expect(hasCustomName(' 工具 ', 'a/b'), isTrue);
      expect(hasCustomName('a/b', 'a/b'), isFalse);
      expect(hasCustomName(null, 'a/b'), isFalse);
      expect(hasCustomName('  ', 'a/b'), isFalse);
    });
  });
}
