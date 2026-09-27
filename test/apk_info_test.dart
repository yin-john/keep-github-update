import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/platform/apk_info.dart';

void main() {
  group('APK 名称/图标解析', () {
    test('正常解析 label 与 iconPath', () {
      final info = ApkAppInfo.fromChannel({
        'label': '示例应用',
        'iconPath': '/data/user/0/pkg/files/grku_icons/com.foo.png',
      });
      expect(info.label, '示例应用');
      expect(info.iconPath, endsWith('/com.foo.png'));
      expect(info.isNotEmpty, isTrue);
    });

    test('缺字段 / 空字符串 / 非 Map 都安全退化', () {
      expect(ApkAppInfo.fromChannel(null).isEmpty, isTrue);
      expect(ApkAppInfo.fromChannel('nope').isEmpty, isTrue);
      expect(ApkAppInfo.fromChannel(<Object>[]).isEmpty, isTrue);
      expect(ApkAppInfo.fromChannel({'label': '  '}).isEmpty, isTrue);
      expect(ApkAppInfo.fromChannel({'iconPath': ''}).isEmpty, isTrue);
    });

    test('只有图标没有名称也能用', () {
      final info = ApkAppInfo.fromChannel({'iconPath': '/tmp/a.png'});
      expect(info.label, isNull);
      expect(info.iconPath, '/tmp/a.png');
      expect(info.isNotEmpty, isTrue);
    });

    test('非字符串值会被转成字符串', () {
      final info = ApkAppInfo.fromChannel({'label': 123});
      expect(info.label, '123');
    });

    test('解析包名与版本（原生 apkAppInfo 返回）', () {
      final info = ApkAppInfo.fromChannel({
        'label': '示例应用',
        'packageName': 'com.example.app',
        'version': '1.2.3',
        'iconPath': '/tmp/a.png',
      });
      expect(info.packageName, 'com.example.app');
      expect(info.version, '1.2.3');
      expect(info.isNotEmpty, isTrue);
    });
  });
}
