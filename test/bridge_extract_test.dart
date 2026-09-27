import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/core/config/rule_presets.dart';
import 'package:github_releases_keep_update/core/platform/bridge.dart';

List<int> _zip() {
  final a = Archive();
  a.addFile(ArchiveFile('app.exe', 3, [1, 2, 3]));
  a.addFile(ArchiveFile('readme.txt', 3, [4, 5, 6]));
  return ZipEncoder().encode(a)!;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('grku_zip_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('默认：清空安装目录后解压', () async {
    final zipPath = '${tmp.path}/a.zip';
    File(zipPath).writeAsBytesSync(_zip());
    final target = Directory('${tmp.path}/t')..createSync(recursive: true);
    File('${target.path}/old.txt').writeAsStringSync('old');

    await const DefaultPlatformBridge().extractZip(zipPath, target.path);

    expect(File('${target.path}/old.txt').existsSync(), isFalse);
    expect(File('${target.path}/app.exe').existsSync(), isTrue);
  });

  test('preserve：匹配的数据目录被保留', () async {
    final zipPath = '${tmp.path}/a.zip';
    File(zipPath).writeAsBytesSync(_zip());
    final target = Directory('${tmp.path}/t')..createSync(recursive: true);
    Directory('${target.path}/data').createSync();
    File('${target.path}/data/keep.txt').writeAsStringSync('keep');
    File('${target.path}/old.txt').writeAsStringSync('old');

    await const DefaultPlatformBridge()
        .extractZip(zipPath, target.path, preserve: [r'^data/']);

    expect(File('${target.path}/data/keep.txt').existsSync(), isTrue); // 保留
    expect(File('${target.path}/old.txt').existsSync(), isFalse); // 清除
    expect(File('${target.path}/app.exe').existsSync(), isTrue); // 新解压
  });

  test('preserve：匹配的数据文件被保留，其余删除', () async {
    final zipPath = '${tmp.path}/a.zip';
    File(zipPath).writeAsBytesSync(_zip());
    final target = Directory('${tmp.path}/t')..createSync(recursive: true);
    File('${target.path}/settings.ini').writeAsStringSync('keep');
    File('${target.path}/old.txt').writeAsStringSync('old');

    await const DefaultPlatformBridge().extractZip(zipPath, target.path,
        preserve: [r'\.ini$']);

    expect(File('${target.path}/settings.ini').existsSync(), isTrue); // 保留
    expect(File('${target.path}/old.txt').existsSync(), isFalse); // 清除
    expect(File('${target.path}/app.exe').existsSync(), isTrue); // 新解压
  });

  group('单文件便携版（portable exe）', () {
    test('压缩包与单文件的判定', () {
      expect(isArchiveFile(r'C:\a\app.zip'), isTrue);
      expect(isArchiveFile('/tmp/app.tar.gz'), isTrue);
      expect(isArchiveFile(r'C:\a\yt-dlp.exe'), isFalse);
      expect(isArchiveFile('/tmp/App.AppImage'), isFalse);
    });

    test('放入安装目录并同名覆盖', () async {
      final src = File('${tmp.path}/yt-dlp.exe')..writeAsStringSync('v2');
      final target = Directory('${tmp.path}/t')..createSync(recursive: true);
      File('${target.path}/yt-dlp.exe').writeAsStringSync('v1');

      await const DefaultPlatformBridge()
          .placePortableFile(src.path, target.path);

      expect(File('${target.path}/yt-dlp.exe').readAsStringSync(), 'v2');
    });

    test('目标目录不存在时自动创建', () async {
      final src = File('${tmp.path}/tool.exe')..writeAsStringSync('bin');
      final target = '${tmp.path}/nested/dir';

      await const DefaultPlatformBridge()
          .placePortableFile(src.path, target);

      expect(File('$target/tool.exe').existsSync(), isTrue);
    });
  });

  group('规则库预设', () {
    test('Windows 提供 Portable EXE 预设且排除 setup', () {
      final presets = systemRulePresets[PlatformType.windows]!;
      final preset = presets.firstWhere((e) => e.name.contains('Portable EXE'));

      expect(preset.rule.strategy, UpdateStrategy.portable);
      final re = RegExp(preset.rule.nameRegex);
      expect(re.hasMatch('yt-dlp.exe'), isTrue);
      expect(re.hasMatch('App-1.2.3-win64.exe'), isTrue);
      expect(re.hasMatch('setup-x64.exe'), isFalse);
    });
  });
}
