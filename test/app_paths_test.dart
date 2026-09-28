import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/app_paths.dart';
import 'package:path/path.dart' as p;

import 'support/fs.dart';

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

  group('resolveAndroidConfigPath（配置与 logs 同父目录）', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('grku_paths_'));
    tearDown(() => deleteDirQuietly(tmp));

    test('公共目录可写：返回公共路径，并把私有旧配置复制过去（不删私有副本）', () {
      final publicRoot = p.join(tmp.path, 'grku');
      final privateDir = p.join(tmp.path, 'private', appDirName);
      Directory(privateDir).createSync(recursive: true);
      File(p.join(privateDir, 'config.yaml'))
          .writeAsStringSync('configVersion: 4\n');
      File(p.join(privateDir, 'repos.yaml'))
          .writeAsStringSync('repos: []\n');
      File(p.join(privateDir, 'config.yaml.bak')).writeAsStringSync('old');

      final cfg = resolveAndroidConfigPath(
        publicRoot: publicRoot,
        privateConfigPath: p.join(privateDir, 'config.yaml'),
      );

      expect(cfg, p.join(publicRoot, 'config.yaml'));
      expect(File(p.join(publicRoot, 'config.yaml')).existsSync(), isTrue);
      expect(File(p.join(publicRoot, 'repos.yaml')).existsSync(), isTrue);
      expect(File(p.join(publicRoot, 'config.yaml.bak')).existsSync(), isTrue);
      // 私有副本保留（权限撤销后的兜底）
      expect(File(p.join(privateDir, 'config.yaml')).existsSync(), isTrue);
    });

    test('公共目录已有 config.yaml：不覆盖，直接使用', () {
      final publicRoot = p.join(tmp.path, 'grku');
      Directory(publicRoot).createSync(recursive: true);
      File(p.join(publicRoot, 'config.yaml'))
          .writeAsStringSync('configVersion: 4\nnew: true\n');
      final privateDir = p.join(tmp.path, 'private', appDirName);
      Directory(privateDir).createSync(recursive: true);
      File(p.join(privateDir, 'config.yaml')).writeAsStringSync('old: true\n');

      final cfg = resolveAndroidConfigPath(
        publicRoot: publicRoot,
        privateConfigPath: p.join(privateDir, 'config.yaml'),
      );

      expect(cfg, p.join(publicRoot, 'config.yaml'));
      expect(File(cfg).readAsStringSync(), contains('new: true'));
    });

    test('公共目录不可写：回退私有路径', () {
      // Windows：路径含非法字符；其它平台：/proc 只读
      final badRoot = Platform.isWindows
          ? p.join(tmp.path, 'inva<l>d', 'grku')
          : '/proc/grku_nonexistent_probe';
      final cfg = resolveAndroidConfigPath(
        publicRoot: badRoot,
        privateConfigPath: p.join(tmp.path, 'private', 'config.yaml'),
      );
      expect(cfg, p.join(tmp.path, 'private', 'config.yaml'));
    });

    test('私有目录不存在（全新安装）：直接用公共路径', () {
      final publicRoot = p.join(tmp.path, 'grku');
      final cfg = resolveAndroidConfigPath(
        publicRoot: publicRoot,
        privateConfigPath: p.join(tmp.path, 'nope', 'config.yaml'),
      );
      expect(cfg, p.join(publicRoot, 'config.yaml'));
      expect(Directory(publicRoot).existsSync(), isTrue);
    });
  });
}
