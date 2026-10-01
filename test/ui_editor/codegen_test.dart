import 'package:flutter_test/flutter_test.dart';

import '../../tool/ui_editor/codegen.dart';
import '../../tool/ui_editor/dart_emitter.dart';

UiNode _leaf(String type, [Map<String, Object?> props = const <String, Object?>{}]) =>
    UiNode(type: type, props: props, children: <UiNode>[]);

void main() {
  test('生成完整的 StatelessWidget 文件', () {
    final tree = UiNode(
      type: 'Column',
      props: <String, Object?>{},
      children: <UiNode>[_leaf('Text', <String, Object?>{'data': 'Hello'})],
    );
    final source = generateSource(className: 'Demo', root: tree);

    expect(source.startsWith(kGeneratedHeader), isTrue);
    expect(source, contains("import 'package:flutter/material.dart';"));
    expect(source, contains('class Demo extends StatelessWidget {'));
    expect(source, contains('const Demo({super.key});'));
    expect(source, contains('Widget build(BuildContext context) {'));
    expect(
      source,
      contains("return const Column(children: <Widget>[Text('Hello')]);"),
    );
  });

  test('构造器声明在 build 之前（sort_constructors_first）', () {
    final source = generateSource(className: 'Demo', root: _leaf('Text'));
    expect(
      source.indexOf('const Demo({super.key});'),
      lessThan(source.indexOf('Widget build(BuildContext context)')),
    );
  });

  test('用到 Image.file 时包含 dart:io', () {
    final source = generateSource(
      className: 'Demo',
      root: _leaf('Image.file', <String, Object?>{'path': '/tmp/a.png'}),
    );
    expect(source, contains("import 'dart:io';"));
  });

  test('未用到 dart:io 时不产出该 import（避免 unused_import）', () {
    final source = generateSource(className: 'Demo', root: _leaf('Text'));
    expect(source, isNot(contains("import 'dart:io';")));
  });

  test('生成是幂等的', () {
    final tree = UiNode(
      type: 'Column',
      props: <String, Object?>{},
      children: <UiNode>[_leaf('Text'), _leaf('SizedBox')],
    );
    expect(
      generateSource(className: 'Demo', root: tree),
      generateSource(className: 'Demo', root: tree),
    );
  });
}
