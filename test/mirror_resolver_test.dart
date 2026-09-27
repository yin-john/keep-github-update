import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/core/mirror/mirror_resolver.dart';

void main() {
  group('MirrorResolver', () {
    test('prefix 模式替换 github.com 前缀', () {
      const resolver = MirrorResolver([
        const MirrorConfig(
          name: 'ghproxy',
          mode: MirrorMode.prefix,
          pattern: 'https://github.com',
          replacement: 'https://ghproxy.com/https://github.com',
        ),
      ]);
      final out = resolver.resolve(
          'https://github.com/owner/repo/releases/download/v1/a.zip');
      expect(out,
          'https://ghproxy.com/https://github.com/owner/repo/releases/download/v1/a.zip');
    });

    test('regex 模式改写 host', () {
      const resolver = MirrorResolver([
        const MirrorConfig(
          name: 'regex',
          mode: MirrorMode.regex,
          pattern: r'github\.com',
          replacement: 'mirror.example.com',
        ),
      ]);
      final out = resolver.resolve(
          'https://github.com/owner/repo/releases/download/v1/a.zip');
      expect(out,
          'https://mirror.example.com/owner/repo/releases/download/v1/a.zip');
    });

    test('无匹配规则时原样返回', () {
      const resolver = MirrorResolver(const []);
      expect(resolver.resolve('https://github.com/x/y'), 'https://github.com/x/y');
    });

    test('未填写完整的镜像被跳过，不会污染下载地址', () {
      const resolver = MirrorResolver([
        const MirrorConfig(
          name: 'blank',
          mode: MirrorMode.prefix,
          pattern: '',
          replacement: '',
        ),
        const MirrorConfig(
          name: 'prefix-no-replacement',
          mode: MirrorMode.prefix,
          pattern: 'https://github.com',
          replacement: '',
        ),
      ]);
      const url = 'https://github.com/owner/repo/releases/download/v1/a.zip';
      expect(resolver.resolve(url), url);
    });
  });
}
