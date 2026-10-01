import 'package:flutter_test/flutter_test.dart';

import '../../tool/ui_editor/dart_emitter.dart';

/// 构造一个叶子节点（无子节点）。
UiNode leaf(String type, [Map<String, Object?> props = const <String, Object?>{}]) =>
    UiNode(type: type, props: props, children: <UiNode>[]);

/// 渲染单节点。
String emit(UiNode node) => DartEmitter().emit(node);

void main() {
  group('const 传播', () {
    test('独立 Text 会加上 const', () {
      expect(emit(leaf('Text')), r"const Text('Text')");
    });

    test('整棵可 const 的子树只在最外层加一次 const', () {
      final tree = UiNode(
        type: 'Column',
        props: <String, Object?>{},
        children: <UiNode>[leaf('Text'), leaf('SizedBox')],
      );
      expect(
        emit(tree),
        r"const Column(children: <Widget>[Text('Text'), SizedBox()])",
      );
    });

    test('父节点不可 const 时，可 const 的兄弟各自加 const', () {
      final tree = UiNode(
        type: 'Column',
        props: <String, Object?>{},
        children: <UiNode>[leaf('Text'), leaf('ElevatedButton')],
      );
      expect(
        emit(tree),
        r"Column(children: <Widget>[const Text('Text'), "
        r"ElevatedButton(onPressed: () {}, child: const Text('按钮'))])",
      );
    });

    test('Container 不是 const 构造器，自身不加 const', () {
      final tree = UiNode(
        type: 'Container',
        props: <String, Object?>{},
        children: <UiNode>[leaf('Text')],
      );
      expect(emit(tree), r"Container(child: const Text('Text'))");
    });

    test('Image.file 不是 const 构造器', () {
      expect(
        emit(leaf('Image.file', <String, Object?>{'path': '/tmp/a.png'})),
        r"Image.file(File('/tmp/a.png'))",
      );
    });

    test('父节点可 const 时，子节点不再重复 const', () {
      final tree = UiNode(
        type: 'Center',
        props: <String, Object?>{},
        children: <UiNode>[leaf('Text')],
      );
      expect(emit(tree), r"const Center(child: Text('Text'))");
    });
  });

  group('字面量格式化', () {
    test('字符串转义：单引号 / 美元 / 反斜杠 / 换行', () {
      expect(emit(leaf('Text', <String, Object?>{'data': "it's"})),
          r"const Text('it\'s')");
      expect(emit(leaf('Text', <String, Object?>{'data': r'$x'})),
          r"const Text('\$x')");
      expect(emit(leaf('Text', <String, Object?>{'data': r'a\b'})),
          r"const Text('a\\b')");
      expect(emit(leaf('Text', <String, Object?>{'data': 'a\nb'})),
          r"const Text('a\nb')");
    });

    test('整数值补 .0，小数原样', () {
      expect(emit(leaf('SizedBox', <String, Object?>{'height': 12})),
          r'const SizedBox(height: 12.0)');
      expect(emit(leaf('SizedBox', <String, Object?>{'height': 12.5})),
          r'const SizedBox(height: 12.5)');
    });

    test('颜色统一为 Color(0x…) 且大写', () {
      expect(
        emit(leaf('Text', <String, Object?>{'color': '#1e293b'})),
        r"const Text('Text', style: TextStyle(color: Color(0xFF1E293B)))",
      );
    });

    test('枚举带类型前缀', () {
      final tree = UiNode(
        type: 'Column',
        props: <String, Object?>{'mainAxisAlignment': 'center'},
        children: <UiNode>[],
      );
      expect(emit(tree), 'const Column(mainAxisAlignment: MainAxisAlignment.center)');
    });

    test('图标名映射为 Icons.<name>', () {
      expect(emit(leaf('Icon', <String, Object?>{'icon': 'add'})),
          r'const Icon(Icons.add)');
    });

    test('EdgeInsets / BorderRadius', () {
      final tree = UiNode(
        type: 'Padding',
        props: <String, Object?>{'padding': 12},
        children: <UiNode>[leaf('Text')],
      );
      expect(emit(tree), r"const Padding(padding: EdgeInsets.all(12.0), child: Text('Text'))");

      final box = UiNode(
        type: 'Container',
        props: <String, Object?>{'radius': 8},
        children: <UiNode>[],
      );
      expect(emit(box),
          r'Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8.0)))');
    });

    test('Container 只有颜色时可 const 的 BoxDecoration 会加 const', () {
      final box = UiNode(
        type: 'Container',
        props: <String, Object?>{'color': '#1E293B'},
        children: <UiNode>[],
      );
      expect(
        emit(box),
        r'Container(decoration: const BoxDecoration(color: Color(0xFF1E293B)))',
      );
    });

    test('Checkbox 的必填参数始终产出', () {
      expect(emit(leaf('Checkbox')),
          r'Checkbox(value: false, onChanged: (v) {})');
    });

    test('enabled 为 false 时回调传 null', () {
      expect(
        emit(leaf('ElevatedButton', <String, Object?>{'enabled': false})),
        r"const ElevatedButton(onPressed: null, child: Text('按钮'))",
      );
    });
  });

  group('import 推导', () {
    test('用到 Image.file 时记录 dart:io', () {
      final emitter = DartEmitter()
        ..emit(leaf('Image.file', <String, Object?>{'path': '/tmp/a.png'}));
      expect(emitter.usedImports, contains('dart:io'));
    });

    test('未用到时不记录 dart:io', () {
      final emitter = DartEmitter()..emit(leaf('Text'));
      expect(emitter.usedImports, isNot(contains('dart:io')));
    });
  });

  group('非法输入', () {
    test('未知组件类型', () {
      expect(() => emit(leaf('Nope')), throwsA(isA<CodegenException>()));
    });

    test('none 组件不接受子节点', () {
      final tree = UiNode(
        type: 'Text',
        props: <String, Object?>{},
        children: <UiNode>[leaf('Text')],
      );
      expect(() => emit(tree), throwsA(isA<CodegenException>()));
    });

    test('single 组件最多一个子节点', () {
      final tree = UiNode(
        type: 'Center',
        props: <String, Object?>{},
        children: <UiNode>[leaf('Text'), leaf('Text')],
      );
      expect(() => emit(tree), throwsA(isA<CodegenException>()));
    });

    test('属性类型不符', () {
      expect(
        () => emit(leaf('SizedBox', <String, Object?>{'height': 'tall'})),
        throwsA(isA<CodegenException>()),
      );
    });

    test('非法颜色值', () {
      expect(
        () => emit(leaf('Text', <String, Object?>{'color': 'red'})),
        throwsA(isA<CodegenException>()),
      );
    });

    test('UiNode.fromJson 拒绝缺 type 的节点', () {
      expect(() => UiNode.fromJson(<String, Object?>{'props': <String, Object?>{}}),
          throwsA(isA<CodegenException>()));
    });

    test('UiNode.fromJson 解析嵌套树', () {
      final node = UiNode.fromJson(<String, Object?>{
        'type': 'Column',
        'props': <String, Object?>{},
        'children': <Object?>[
          <String, Object?>{'type': 'Text', 'props': <String, Object?>{'data': 'hi'}},
        ],
      });
      expect(node.children.single.type, 'Text');
    });
  });
}
