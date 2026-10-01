import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ui_editor/widget_catalog.dart';

void main() {
  test('组件类型名唯一且合法', () {
    final seen = <String>{};
    for (final spec in kCatalog) {
      expect(
        spec.type,
        matches(RegExp(r'^[A-Z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)?$')),
        reason: '非法类型名：${spec.type}',
      );
      expect(seen.add(spec.type), isTrue, reason: '重复类型名：${spec.type}');
    }
  });

  test('枚举属性必须有可选值与 dartType，且默认值落在可选值内', () {
    for (final spec in kCatalog) {
      for (final prop in spec.props) {
        if (prop.type != PropType.enumValue) {
          continue;
        }
        final where = '${spec.type}.${prop.name}';
        expect(prop.values, isNotEmpty, reason: '$where 缺少 values');
        expect(prop.dartType, isNotNull, reason: '$where 缺少 dartType');
        if (prop.defaultValue != null) {
          expect(prop.values, contains(prop.defaultValue),
              reason: '$where 的默认值不在 values 内');
        }
      }
    }
  });

  test('图标属性必须有白名单，且默认值在白名单内', () {
    for (final spec in kCatalog) {
      for (final prop in spec.props) {
        if (prop.type != PropType.icon && prop.type != PropType.iconWidget) {
          continue;
        }
        final where = '${spec.type}.${prop.name}';
        expect(prop.values, isNotEmpty, reason: '$where 缺少图标白名单');
        expect(prop.values, contains(prop.defaultValue),
            reason: '$where 的默认值不在白名单内');
      }
    }
  });

  test('非空属性都必须有默认值', () {
    for (final spec in kCatalog) {
      for (final prop in spec.props) {
        if (!prop.nullable) {
          expect(prop.defaultValue, isNotNull,
              reason: '${spec.type}.${prop.name} 非空但没有默认值');
        }
      }
    }
  });

  test('positionalProp / labelProp 必须指向真实属性', () {
    for (final spec in kCatalog) {
      if (spec.positionalProp != null) {
        expect(spec.props.any((p) => p.name == spec.positionalProp), isTrue,
            reason: '${spec.type} 的 positionalProp 不存在');
      }
      if (spec.labelProp != null) {
        expect(spec.props.any((p) => p.name == spec.labelProp), isTrue,
            reason: '${spec.type} 的 labelProp 不存在');
      }
    }
  });

  test('回调组件必须声明 callbackArg', () {
    for (final spec in kCatalog) {
      if (spec.callbackParam.isNotEmpty) {
        expect(spec.callbackArg, isNotNull, reason: '${spec.type} 有 callbackParam 但没有 callbackArg');
      }
    }
  });

  test('toJson 可 JSON 往返且条目数一致', () {
    final encoded = jsonEncode(kCatalog.map((s) => s.toJson()).toList());
    final decoded = jsonDecode(encoded) as List<Object?>;
    expect(decoded.length, kCatalog.length);
  });

  test('specFor 命中已知类型、未知返回 null', () {
    expect(specFor('Text'), isNotNull);
    expect(specFor('不存在的组件'), isNull);
  });
}
