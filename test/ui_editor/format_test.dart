import 'package:flutter_test/flutter_test.dart';

import '../../tool/ui_editor/format.dart';

void main() {
  group('isSourceScriptUri', () {
    test('源码形态：file: 且以 .dart 结尾', () {
      expect(
        isSourceScriptUri(Uri.file('/repo/tool/ui_editor.dart')),
        isTrue,
      );
    });

    test('AOT 可执行文件不算源码', () {
      // `dart compile exe` 产物的 Platform.script 指向二进制本身。若误判为源码，
      // 就会用 `Platform.resolvedExecutable format ...` 再拉起一个编辑器服务，
      // 导致 /api/save 永久挂起。
      expect(
        isSourceScriptUri(Uri.file('/tmp/grku_editor/ui_editor')),
        isFalse,
      );
    });

    test('kernel 快照（.dill）不算源码', () {
      expect(
        isSourceScriptUri(Uri.file('/tmp/ui_editor.dill')),
        isFalse,
      );
    });

    test('非 file: 协议不算源码', () {
      expect(isSourceScriptUri(Uri.parse('data:application/dart,x')), isFalse);
      expect(isSourceScriptUri(Uri.parse('http://example.com/ui_editor.dart')),
          isFalse);
    });
  });
}
