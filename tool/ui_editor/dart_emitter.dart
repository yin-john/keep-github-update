/// 把 UI 组件树（JSON）编译成 Dart 源码表达式。
///
/// 纯字符串函数，**不 import `package:flutter/*`**，因此可在 `dart run` 与
/// `flutter test` 下直接单测。
///
/// 核心难点是满足 `prefer_const_constructors`（CI 零容忍）：本文件用
/// [DartExpr] 携带「是否为常量表达式」与「能否加 const 前缀」，渲染时按
/// `inConstContext` 决定在哪一层加 `const`——**只在最外层加一次**，内层不再重复。
library;

import 'dart_string.dart';
import 'widget_catalog.dart';

/// 组件树非法时抛出。
class CodegenException implements Exception {
  CodegenException(this.message);

  final String message;

  @override
  String toString() => 'CodegenException: $message';
}

/// 组件树节点。
class UiNode {
  UiNode({required this.type, required this.props, required this.children});

  /// 从 JSON 解析并校验结构。
  factory UiNode.fromJson(Object? json) {
    if (json is! Map) {
      throw CodegenException('节点必须是对象，实际为 ${json.runtimeType}');
    }
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw CodegenException('节点缺少合法的 type');
    }

    final props = <String, Object?>{};
    final rawProps = json['props'];
    if (rawProps != null) {
      if (rawProps is! Map) {
        throw CodegenException('$type 的 props 必须是对象');
      }
      rawProps.forEach((key, value) {
        if (key is! String) {
          throw CodegenException('$type 的 props 键必须是字符串');
        }
        props[key] = value;
      });
    }

    final children = <UiNode>[];
    final rawChildren = json['children'];
    if (rawChildren != null) {
      if (rawChildren is! List) {
        throw CodegenException('$type 的 children 必须是数组');
      }
      for (final child in rawChildren) {
        children.add(UiNode.fromJson(child));
      }
    }

    return UiNode(type: type, props: props, children: children);
  }

  final String type;
  final Map<String, Object?> props;
  final List<UiNode> children;
}

/// 一个可渲染的 Dart 表达式。
///
/// [build] 接收「内部 const 上下文」并返回**不含 const 前缀**的代码；
/// [render] 负责决定是否加 `const ` 前缀，并把正确的上下文透传给子表达式。
class DartExpr {
  DartExpr(this.build, {required this.isConst, this.prefixable = false});

  /// 叶子表达式（自身不含子表达式）。
  factory DartExpr.leaf(
    String code, {
    required bool isConst,
    bool prefixable = false,
  }) =>
      DartExpr((bool _) => code, isConst: isConst, prefixable: prefixable);

  final String Function(bool inConstContext) build;

  /// 是否满足「常量表达式」（可用于 const 上下文）。
  final bool isConst;

  /// 自身是否为 const 构造器（决定能否加 `const ` 前缀）。
  final bool prefixable;

  String render(bool inConstContext) {
    final selfConst = prefixable && isConst && !inConstContext;
    final inner = build(inConstContext || selfConst);
    return selfConst ? 'const $inner' : inner;
  }
}

/// 组件树 → Dart 表达式。
class DartEmitter {
  DartEmitter({Map<String, WidgetSpec>? catalog})
      : _catalog = catalog ?? kCatalogByType;

  final Map<String, WidgetSpec> _catalog;
  final Set<String> _usedImports = <String>{};

  /// 本次生成过程中用到的额外 import（如 `dart:io`）。
  Set<String> get usedImports => Set<String>.unmodifiable(_usedImports);

  /// 渲染根节点为 Dart 表达式源码。
  String emit(UiNode root) {
    _usedImports.clear();
    return _emitNode(root).render(false);
  }

  DartExpr _emitNode(UiNode node) {
    final spec = _catalog[node.type];
    if (spec == null) {
      throw CodegenException('未知组件类型：${node.type}');
    }
    _validateChildren(spec, node);
    for (final import in spec.imports) {
      _usedImports.add(import);
    }

    final childExprs = <DartExpr>[
      for (final child in node.children) _emitNode(child),
    ];

    final positional = <DartExpr>[];
    final named = <String, DartExpr>{};
    final groups = <String, List<MapEntry<String, DartExpr>>>{};
    var argsConst = true;

    for (final prop in spec.props) {
      if (prop.name == spec.positionalProp) {
        final raw = _valueOf(node, prop);
        if (raw == null) {
          throw CodegenException('${spec.type} 的位置参数 ${prop.name} 不能为空');
        }
        final expr = _formatValue(prop, raw);
        positional.add(expr);
        argsConst = argsConst && expr.isConst;
        continue;
      }
      // label 会转成 child: Text(...)，enabled 是虚拟开关，都不是 Dart 参数。
      if (prop.name == spec.labelProp || prop.name == 'enabled') {
        continue;
      }
      final raw = _valueOf(node, prop);
      if (!prop.required) {
        if (prop.nullable) {
          if (raw == null) {
            continue;
          }
        } else if (raw == prop.defaultValue) {
          continue;
        }
      }
      final expr = _formatValue(prop, raw);
      argsConst = argsConst && expr.isConst;
      if (prop.group.isEmpty) {
        named[prop.dartArg] = expr;
      } else {
        groups
            .putIfAbsent(prop.group, () => <MapEntry<String, DartExpr>>[])
            .add(MapEntry<String, DartExpr>(prop.dartArg, expr));
      }
    }

    // 回调：enabled 为 false 时传 null（常量），否则给一个空闭包（非常量）。
    final callbackArg = spec.callbackArg;
    if (callbackArg != null) {
      final enabled = node.props['enabled'] ?? true;
      final DartExpr callback;
      if (enabled == true) {
        callback = DartExpr(
          (bool _) => spec.callbackParam.isEmpty
              ? '() {}'
              : '(${spec.callbackParam}) {}',
          isConst: false,
        );
      } else {
        callback = DartExpr.leaf('null', isConst: true);
      }
      named[callbackArg] = callback;
      argsConst = argsConst && callback.isConst;
    }

    // 按钮类：label → child: Text('…')。
    final labelProp = spec.labelProp;
    if (labelProp != null) {
      final propSpec = spec.props.firstWhere((p) => p.name == labelProp);
      final raw = _valueOf(node, propSpec) ?? propSpec.defaultValue ?? '';
      final childExpr = DartExpr(
        (bool _) => 'Text(${dartString(raw.toString())})',
        isConst: true,
        prefixable: true,
      );
      named['child'] = childExpr;
      argsConst = argsConst && childExpr.isConst;
    }

    final childrenConst = childExprs.every((e) => e.isConst);
    final nodeIsConst = spec.hasConstCtor && argsConst && childrenConst;

    final build = (bool ctx) {
      final parts = <String>[];
      for (final expr in positional) {
        parts.add(expr.render(ctx));
      }
      named.forEach((String key, DartExpr expr) {
        parts.add('$key: ${expr.render(ctx)}');
      });
      groups.forEach((String groupName, List<MapEntry<String, DartExpr>> members) {
        final ctor = kGroupConstructors[groupName] ?? groupName;
        final memberConst = members.every((m) => m.value.isConst);
        final groupExpr = DartExpr(
          (bool c) =>
              '$ctor(${members.map((m) => '${m.key}: ${m.value.render(c)}').join(', ')})',
          isConst: memberConst,
          prefixable: true,
        );
        parts.add('$groupName: ${groupExpr.render(ctx)}');
      });
      if (childExprs.isNotEmpty) {
        if (spec.children == ChildrenMode.single) {
          parts.add('child: ${childExprs.first.render(ctx)}');
        } else {
          final items = childExprs.map((e) => e.render(ctx)).join(', ');
          parts.add('children: <Widget>[$items]');
        }
      }
      return '${spec.type}(${parts.join(', ')})';
    };

    return DartExpr(
      build,
      isConst: nodeIsConst,
      prefixable: spec.hasConstCtor,
    );
  }

  void _validateChildren(WidgetSpec spec, UiNode node) {
    if (spec.children == ChildrenMode.none && node.children.isNotEmpty) {
      throw CodegenException('${spec.type} 不接受子节点');
    }
    if (spec.children == ChildrenMode.single && node.children.length > 1) {
      throw CodegenException('${spec.type} 最多接受一个子节点');
    }
  }

  Object? _valueOf(UiNode node, PropSpec prop) => node.props.containsKey(prop.name)
      ? node.props[prop.name]
      : prop.defaultValue;

  DartExpr _formatValue(PropSpec prop, Object? raw) {
    try {
      return _formatValueUnsafe(prop, raw);
    } on ArgumentError catch (e) {
      // dart_string 层抛的是 ArgumentError；统一收敛成 CodegenException，
      // 便于服务端映射为 400 而不是 500。
      throw CodegenException('属性 ${prop.name} 取值非法：${e.message}');
    }
  }

  // 用 switch 表达式：编译器强制穷尽，无需兜底分支（有兜底反而触发 dead_code）。
  DartExpr _formatValueUnsafe(PropSpec prop, Object? raw) => switch (prop.type) {
        PropType.string ||
        PropType.multilineString =>
          DartExpr.leaf(dartString(_asString(raw, prop)), isConst: true),
        PropType.bool =>
          DartExpr.leaf(_asBool(raw, prop) ? 'true' : 'false', isConst: true),
        PropType.int => DartExpr.leaf('${_asInt(raw, prop)}', isConst: true),
        PropType.double =>
          DartExpr.leaf(dartDouble(_asDouble(raw, prop)), isConst: true),
        PropType.color => DartExpr.leaf(
            dartColor(_asString(raw, prop)),
            isConst: true,
            prefixable: true,
          ),
        PropType.icon =>
          DartExpr.leaf(dartIcon(_asString(raw, prop)), isConst: true),
        PropType.iconWidget => DartExpr.leaf(
            'Icon(${dartIcon(_asString(raw, prop))})',
            isConst: true,
            prefixable: true,
          ),
        PropType.filePath => DartExpr.leaf(
            'File(${dartString(_asString(raw, prop))})',
            isConst: false,
          ),
        PropType.enumValue => _enumValueExpr(prop, raw),
        PropType.edgeInsets => DartExpr.leaf(
            dartEdgeInsetsAll(_asDouble(raw, prop)),
            isConst: true,
            prefixable: true,
          ),
        PropType.borderRadius => DartExpr.leaf(
            dartBorderRadiusCircular(_asDouble(raw, prop)),
            isConst: false,
          ),
        PropType.fontWeight => DartExpr.leaf(
            _asBool(raw, prop) ? 'FontWeight.bold' : 'FontWeight.normal',
            isConst: true,
          ),
      };

  DartExpr _enumValueExpr(PropSpec prop, Object? raw) {
    final dartType = prop.dartType;
    if (dartType == null) {
      throw CodegenException('属性 ${prop.name} 缺少 dartType');
    }
    return DartExpr.leaf(dartEnum(dartType, _asString(raw, prop)), isConst: true);
  }
}

String _asString(Object? raw, PropSpec prop) {
  if (raw is String) {
    return raw;
  }
  throw CodegenException('属性 ${prop.name} 需要字符串，实际为 ${raw.runtimeType}');
}

bool _asBool(Object? raw, PropSpec prop) {
  if (raw is bool) {
    return raw;
  }
  throw CodegenException('属性 ${prop.name} 需要布尔值，实际为 ${raw.runtimeType}');
}

int _asInt(Object? raw, PropSpec prop) {
  if (raw is int) {
    return raw;
  }
  if (raw is num && raw == raw.roundToDouble()) {
    return raw.toInt();
  }
  throw CodegenException('属性 ${prop.name} 需要整数，实际为 ${raw.runtimeType}');
}

double _asDouble(Object? raw, PropSpec prop) {
  if (raw is num) {
    return raw.toDouble();
  }
  throw CodegenException('属性 ${prop.name} 需要数字，实际为 ${raw.runtimeType}');
}
