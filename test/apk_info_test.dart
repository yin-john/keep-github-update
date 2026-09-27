import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/platform/apk_info.dart';
import 'package:github_releases_keep_update/core/platform/apk_local_info.dart';

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

  group('Xposed 模块标记', () {
    test('原生返回 xposed=true（布尔或字符串）都能识别', () {
      expect(ApkAppInfo.fromChannel({'label': 'a', 'xposed': true}).xposed,
          isTrue);
      expect(
          ApkAppInfo.fromChannel({'label': 'a', 'xposed': 'true'}).xposed,
          isTrue);
      expect(
          ApkAppInfo.fromChannel({'label': 'a', 'xposed': false}).xposed,
          isFalse);
      expect(
          ApkAppInfo.fromChannel({'label': 'a', 'xposed': 'nope'}).xposed,
          isFalse);
      expect(ApkAppInfo.fromChannel({'label': 'a'}).xposed, isFalse);
    });

    test('xposed 不参与 isEmpty 判断', () {
      expect(ApkAppInfo.fromChannel({'xposed': true}).isEmpty, isTrue);
    });

    test('信息文本写入并解析回 Xposed 标记', () {
      final info = const ApkAppInfo(
          label: '模块A',
          packageName: 'com.example.mod',
          version: '1.0',
          xposed: true);
      final txt = formatApkInfoTxt(info);
      expect(txt, contains('Xposed 模块: 是'));
      final parsed = parseApkInfoTxt(txt);
      expect(parsed.xposed, isTrue);
      expect(parsed.label, '模块A');
    });

    test('普通应用的信息文本不含 Xposed 行，解析为 false', () {
      final txt = formatApkInfoTxt(
          const ApkAppInfo(label: '普通应用', version: '2.0'));
      expect(txt, isNot(contains('Xposed')));
      expect(parseApkInfoTxt(txt).xposed, isFalse);
    });

    test('旧格式（无 Xposed 行）兼容解析', () {
      final parsed = parseApkInfoTxt('名称: 老应用\n包名: com.old\n版本: 0.1\n');
      expect(parsed.xposed, isFalse);
      expect(parsed.label, '老应用');
    });
  });
}
