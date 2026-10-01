import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/ui_editor/project.dart';
import '../support/fs.dart';

void main() {
  group('validateClassName', () {
    test('合法类名', () {
      expect(validateClassName('Foo'), isNull);
      expect(validateClassName('MyWidget2'), isNull);
    });

    test('非法类名', () {
      expect(validateClassName(''), isNotNull);
      expect(validateClassName('foo'), isNotNull);
      expect(validateClassName('Foo/Bar'), isNotNull);
      expect(validateClassName('../evil'), isNotNull);
      expect(validateClassName('Foo-Bar'), isNotNull);
      expect(validateClassName('Foo.Bar'), isNotNull);
      expect(validateClassName(List<String>.filled(65, 'A').join()), isNotNull);
    });

    test('Dart 保留字', () {
      // 首字母大写的保留字（Function）能通过正则，必须由保留字表拦下。
      expect(validateClassName('Function'), isNotNull);
    });
  });

  group('写入沙箱', () {
    test('生成目标固定在 lib/ui/generated 下', () {
      final root = Directory.systemTemp.createTempSync('grku_proj');
      addTearDown(() => deleteDirQuietly(root));
      final file = resolveGeneratedTarget(root, 'Demo');
      expect(
        p.relative(file.path, from: root.path),
        p.join('lib', 'ui', 'generated', 'Demo.dart'),
      );
    });

    test('非法类名解析目标时抛错', () {
      final root = Directory.systemTemp.createTempSync('grku_proj');
      addTearDown(() => deleteDirQuietly(root));
      expect(
        () => resolveGeneratedTarget(root, '../evil'),
        throwsArgumentError,
      );
    });

    test('ensureGeneratedDir 按需创建目录', () {
      final root = Directory.systemTemp.createTempSync('grku_proj');
      addTearDown(() => deleteDirQuietly(root));
      final dir = ensureGeneratedDir(root);
      expect(dir.existsSync(), isTrue);
    });
  });

  test('findProjectRoot 能定位到含 pubspec.yaml 的目录', () {
    final root = findProjectRoot(Directory.current);
    expect(File(p.join(root.path, 'pubspec.yaml')).existsSync(), isTrue);
  });
}
