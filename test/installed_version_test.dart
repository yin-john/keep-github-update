import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/version/installed_version.dart';

void main() {
  group('版本比较', () {
    test('归一化去掉 v 前缀与空白', () {
      expect(normalizeVersion(' V1.2.3 '), '1.2.3');
      expect(normalizeVersion('v 1.2.3'), '1.2.3');
      expect(normalizeVersion(null), '');
    });

    test('提取版本核心', () {
      expect(versionCore('app-v1.2.3-beta'), '1.2.3');
      expect(versionCore('release-2024.05'), '2024.05');
      expect(versionCore('no-digits'), '');
    });

    test('不同书写视为同一版本', () {
      expect(versionMatches('1.2.3', 'v1.2.3'), isTrue);
      expect(versionMatches('1.2', '1.2.0'), isTrue);
      expect(versionMatches('v2.0.0', '2.0.0-release'), isTrue);
    });

    test('不同版本不匹配', () {
      expect(versionMatches('1.2.3', '1.2.30'), isFalse);
      expect(versionMatches('1.9.0', 'v2.0.0'), isFalse);
      expect(versionMatches('', 'v1'), isFalse);
      expect(versionMatches(null, null), isFalse);
    });

    test('比较与新旧判断', () {
      expect(compareVersions('1.2.3', '1.2.3'), 0);
      expect(compareVersions('1.2.3', '1.3'), lessThan(0));
      expect(compareVersions('2.0', '1.9.9'), greaterThan(0));
      expect(versionIsNewer('v1.3', '1.2.3'), isTrue);
      expect(versionIsNewer('v1.2.3', '1.2.3'), isFalse);
      expect(versionIsNewer('v1', null), isTrue); // 未安装 → 视为需要更新
    });
  });

  group('module.prop', () {
    const prop = '''
id=my_module
name=My Module
version=v1.2.3
versionCode=123
updateJson=https://raw.githubusercontent.com/acme/MyModule/main/update.json
author=acme
''';

    test('解析字段', () {
      final p = parseModuleProp(prop);
      expect(p.id, 'my_module');
      expect(p.name, 'My Module');
      expect(p.version, 'v1.2.3');
      expect(p.versionCode, '123');
      expect(p.updateJson, contains('acme/MyModule'));
      expect(p.display, 'v1.2.3');
    });

    test('缺少 version 时回退 versionCode', () {
      expect(parseModuleProp('id=x\nversionCode=42\n').display, '42');
    });

    test('解析 shell 分段输出', () {
      const raw = '@@mod_a\nid=mod_a\nversion=1.0\n'
          '@@mod_b\nid=mod_b\nversion=2.0\n';
      final m = parseModuleSections(raw);
      expect(m.keys, ['mod_a', 'mod_b']);
      expect(parseModuleProp(m['mod_b']!).version, '2.0');
    });
  });

  group('模块匹配', () {
    final modules = {
      'unrelated': 'id=unrelated\nname=Other\nversion=9.9\n',
      'my_module':
          'id=my_module\nname=MyModule\nversion=1.2.3\nupdateJson=https://raw.githubusercontent.com/acme/MyModule/main/update.json\n',
    };

    test('优先显式 moduleId', () {
      expect(
        matchModuleId(modules, moduleId: 'my_module', owner: 'x', repo: 'y'),
        'my_module',
      );
    });

    test('按 updateJson 指向的仓库匹配', () {
      expect(
        matchModuleId(modules, owner: 'acme', repo: 'MyModule'),
        'my_module',
      );
    });

    test('按模块 id / 名称匹配仓库名', () {
      final m = {'zzz': 'id=zzz\nname=FooBar\nversion=1\n'};
      expect(matchModuleId(m, owner: 'someone', repo: 'foobar'), 'zzz');
    });

    test('无对应模块时返回 null', () {
      expect(matchModuleId(modules, owner: 'acme', repo: 'NotInstalled'), isNull);
      expect(matchModuleId({}, owner: 'a', repo: 'b'), isNull);
    });
  });

  group('已装应用版本', () {
    const dump = '''
Packages:
  Package [com.example.app] (abc123):
    userId=10123
    codePath=/data/app/~~xyz==/com.example.app-1/base.apk
    versionName=1.2.3
    versionCode=123 minSdk=24
  Package [org.other] (def456):
    userId=10456
    versionName=v2.0
''';

    test('解析 dumpsys package 输出', () {
      final m = parsePackageVersions(dump);
      expect(m['com.example.app'], '1.2.3');
      expect(m['org.other'], 'v2.0');
      expect(m.length, 2);
    });

    test('依据已装 tag 反查包名', () {
      final m = parsePackageVersions(dump);
      expect(guessPackageName(m, installedTag: 'v1.2.3'), 'com.example.app');
      expect(guessPackageName(m, installedTag: 'v9.9.9'), isNull);
      expect(guessPackageName(m, installedTag: null), isNull);
    });

    test('LSPosed 模块 tag（versionCode-versionName）也能反查包名', () {
      // Xposed-Modules-Repo 的 tag 形如 <versionCode>-<versionName>，
      // 应用实际 versionName 只有 1.2.3
      final m = parsePackageVersions(dump);
      expect(guessPackageName(m, installedTag: '20950-1.2.3'),
          'com.example.app');
      expect(guessPackageName(m, installedTag: '20950-9.9.9'), isNull);
    });
  });

  group('versionMatchesTag（tag 变体匹配）', () {
    test('常规 tag 保持 versionMatches 行为', () {
      expect(versionMatchesTag('1.2.3', 'v1.2.3'), isTrue);
      expect(versionMatchesTag('1.2.3', '1.2'), isTrue);
      expect(versionMatchesTag('1.2.3', 'v1.2.3-beta'), isTrue);
      expect(versionMatchesTag('1.2.3', 'v1.2.4'), isFalse);
      expect(versionMatchesTag(null, 'v1.2.3'), isFalse);
      expect(versionMatchesTag('1.2.3', null), isFalse);
    });

    test('LSPosed 模块 tag：versionCode-versionName 与应用 versionName 匹配', () {
      expect(versionMatchesTag('1.3.4', '20950-1.3.4'), isTrue);
      expect(versionMatchesTag('v1.3.4', '20950-1.3.4'), isTrue);
      expect(versionMatchesTag('1.3.5', '20950-1.3.4'), isFalse);
      // 后缀不是版本号时回退整段比对，不误判
      expect(versionMatchesTag('1.2.3', 'v1.2.3-beta'), isTrue);
      // 边缘：安装版本与后缀字面相同视为同版本（无害）
      expect(versionMatchesTag('beta', 'v1.2.3-beta'), isTrue);
      // 无 - 的 tag 不受影响
      expect(versionMatchesTag('1.2.3', '1.2.3'), isTrue);
    });
  });

  group('版本记录文件', () {
    test('读取 version 字段', () {
      const f = 'repo: acme/tool\nversion: v1.2.3\nasset: a.zip\n';
      expect(parseVersionFile(f), 'v1.2.3');
      expect(parseVersionFile('repo: a/b\n'), isNull);
    });

    test('拼接记录文件路径', () {
      expect(versionFilePath('/opt/app').endsWith(versionFileName), isTrue);
    });
  });
}
