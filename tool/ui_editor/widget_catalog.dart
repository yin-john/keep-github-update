/// 组件目录：编辑器与代码生成器共用的**唯一事实来源**。
///
/// - `GET /api/palette` 直接把 [kCatalog] 序列化给前端，前端据此渲染组件面板与
///   属性检查器——服务端新增组件无需改一行 JS。
/// - `dart_emitter.dart` 按 `type` 查 [specFor]，决定子节点数量、是否可 const、
///   默认值与各属性的格式化方式。
///
/// 本文件是纯 Dart 数据，**不得 import `package:flutter/*`**。
library;

/// 子节点数量模式。
enum ChildrenMode {
  /// 不接受子节点（如 Text / Icon）。
  none,

  /// 只接受一个子节点（如 Container / Padding）。
  single,

  /// 接受任意多个子节点（如 Column / Row）。
  multi,
}

/// 属性类型：决定前端控件形态与后端字面量格式化。
enum PropType {
  string,
  multilineString,
  bool,
  int,
  double,
  color,

  /// 裸 `Icons.x`（用于 `Icon` 的位置参数）。
  icon,

  /// `Icon(Icons.x)`（用于 `IconButton.icon` 这类 Widget 槽位）。
  iconWidget,

  /// `File('path')`，需要 `dart:io`。
  filePath,

  /// 枚举值，需配合 [PropSpec.dartType]（如 `MainAxisAlignment`）。
  enumValue,

  /// 数值 → `EdgeInsets.all(v)`。
  edgeInsets,

  /// 数值 → `BorderRadius.circular(v)`（工厂构造器，非 const）。
  borderRadius,

  /// 布尔 → `FontWeight.bold`（false 时不产出）。
  fontWeight,
}

/// 一个属性（对应生成代码里的一个命名参数，或某个子构造器的参数）。
class PropSpec {
  const PropSpec({
    required this.name,
    required this.type,
    this.defaultValue,
    this.values = const <String>[],
    this.nullable = false,
    this.required = false,
    this.label = '',
    this.group = '',
    this.arg,
    this.dartType,
  });

  /// 属性名（前端与树 JSON 里的键）。
  final String name;
  final PropType type;
  final Object? defaultValue;

  /// 枚举可选值（前端渲染下拉框）。
  final List<String> values;

  /// 是否允许为空（为空则整个参数省略）。
  final bool nullable;

  /// 是否必填：必填参数即使等于默认值也始终产出。
  final bool required;

  /// 前端显示名（空则用 [name]）。
  final String label;

  /// 归属的子构造器（`style` → TextStyle，`decoration` → BoxDecoration，
  /// `inputDecoration` → InputDecoration）；空表示顶层参数。
  final String group;

  /// 实际产出的命名参数名（空则用 [name]）。
  final String? arg;

  /// 枚举的 Dart 类型名（仅 [PropType.enumValue] 需要）。
  final String? dartType;

  /// 实际产出的命名参数名。
  String get dartArg => arg ?? name;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'type': type.name,
        'defaultValue': defaultValue,
        'values': values,
        'nullable': nullable,
        'required': required,
        'label': label.isEmpty ? name : label,
        'group': group,
        'arg': dartArg,
        'dartType': dartType,
      };
}

/// 一个可拖拽组件的规格。
class WidgetSpec {
  const WidgetSpec({
    required this.type,
    required this.category,
    required this.children,
    required this.hasConstCtor,
    this.props = const <PropSpec>[],
    this.positionalProp,
    this.callbackArg,
    this.callbackParam = '',
    this.labelProp,
    this.imports = const <String>[],
  });

  /// Dart 类名（如 `Column`），也是树 JSON 里的 `type`。
  final String type;
  final String category;
  final ChildrenMode children;

  /// 构造器是否为 `const`——直接决定生成代码能否加 `const` 前缀。
  ///
  /// 必须与 Flutter SDK 一致：标错会产出非法 `const`（编译错误）或漏掉 `const`
  /// （触发 `prefer_const_constructors`，CI 挂）。
  final bool hasConstCtor;

  final List<PropSpec> props;

  /// 位置参数对应的属性名（如 `Text` 的 `data`）。
  final String? positionalProp;

  /// 回调参数名（如 `onPressed` / `onChanged`）；非空表示该组件需要回调。
  final String? callbackArg;

  /// 回调闭包的形参名（空表示 `() {}`，非空表示 `(v) {}`）。
  final String callbackParam;

  /// 字符串属性名：其值会产出为 `child: Text('…')`（按钮类）。
  final String? labelProp;

  /// 该组件额外需要的 import。
  final List<String> imports;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'category': category,
        'children': children.name,
        'hasConstCtor': hasConstCtor,
        'positionalProp': positionalProp,
        'callbackArg': callbackArg,
        'callbackParam': callbackParam,
        'labelProp': labelProp,
        'props': props.map((p) => p.toJson()).toList(),
      };
}

/// 子构造器名 → Dart 类名。
const Map<String, String> kGroupConstructors = <String, String>{
  'style': 'TextStyle',
  'decoration': 'BoxDecoration',
  'inputDecoration': 'InputDecoration',
};

/// 常用枚举可选值。
const List<String> kMainAxisAlignment = <String>[
  'start',
  'center',
  'end',
  'spaceBetween',
  'spaceAround',
  'spaceEvenly',
];
const List<String> kCrossAxisAlignment = <String>[
  'start',
  'center',
  'end',
  'stretch',
  'baseline',
];
const List<String> kMainAxisSize = <String>['max', 'min'];
const List<String> kAlignment = <String>[
  'topLeft',
  'topCenter',
  'topRight',
  'centerLeft',
  'center',
  'centerRight',
  'bottomLeft',
  'bottomCenter',
  'bottomRight',
];
const List<String> kBoxFit = <String>[
  'fill',
  'contain',
  'cover',
  'fitWidth',
  'fitHeight',
  'none',
  'scaleDown',
];

/// 图标白名单：只允许这些名字，避免生成非法标识符。
const List<String> kIconNames = <String>[
  'add', 'arrow_back', 'arrow_forward', 'camera', 'check', 'close',
  'cloud_download', 'dark_mode', 'dashboard', 'delete', 'download', 'edit',
  'error', 'favorite', 'file_copy', 'folder', 'help', 'home', 'image',
  'info', 'light_mode', 'list', 'lock', 'login', 'logout', 'mail', 'menu',
  'more_vert', 'notifications', 'pause', 'person', 'phone', 'play_arrow',
  'refresh', 'save', 'search', 'send', 'settings', 'share', 'star', 'stop',
  'sync', 'upload', 'visibility', 'visibility_off', 'warning',
];

/// 组件目录。
///
/// `hasConstCtor` 已对照 Flutter API 文档核实：
/// - `Container` **不是** const（构造器带 assert 与初始化逻辑）。
/// - `Image.network` / `Image.asset` / `Image.file` **不是** const。
/// - 其余（Column/Row/Padding/Center/SizedBox/Text/Icon/Card/Divider/
///   ElevatedButton/IconButton/TextField/Checkbox）均为 const 构造器。
const List<WidgetSpec> kCatalog = <WidgetSpec>[
  // ————————————— 布局 —————————————
  WidgetSpec(
    type: 'Column',
    category: 'Layout',
    children: ChildrenMode.multi,
    hasConstCtor: true,
    props: <PropSpec>[
      PropSpec(
        name: 'mainAxisAlignment',
        type: PropType.enumValue,
        dartType: 'MainAxisAlignment',
        defaultValue: 'start',
        values: kMainAxisAlignment,
      ),
      PropSpec(
        name: 'crossAxisAlignment',
        type: PropType.enumValue,
        dartType: 'CrossAxisAlignment',
        defaultValue: 'center',
        values: kCrossAxisAlignment,
      ),
      PropSpec(
        name: 'mainAxisSize',
        type: PropType.enumValue,
        dartType: 'MainAxisSize',
        defaultValue: 'max',
        values: kMainAxisSize,
      ),
    ],
  ),
  WidgetSpec(
    type: 'Row',
    category: 'Layout',
    children: ChildrenMode.multi,
    hasConstCtor: true,
    props: <PropSpec>[
      PropSpec(
        name: 'mainAxisAlignment',
        type: PropType.enumValue,
        dartType: 'MainAxisAlignment',
        defaultValue: 'start',
        values: kMainAxisAlignment,
      ),
      PropSpec(
        name: 'crossAxisAlignment',
        type: PropType.enumValue,
        dartType: 'CrossAxisAlignment',
        defaultValue: 'center',
        values: kCrossAxisAlignment,
      ),
      PropSpec(
        name: 'mainAxisSize',
        type: PropType.enumValue,
        dartType: 'MainAxisSize',
        defaultValue: 'max',
        values: kMainAxisSize,
      ),
    ],
  ),
  WidgetSpec(
    type: 'Container',
    category: 'Layout',
    children: ChildrenMode.single,
    // Container 的构造器不是 const。
    hasConstCtor: false,
    props: <PropSpec>[
      PropSpec(name: 'width', type: PropType.double, nullable: true),
      PropSpec(name: 'height', type: PropType.double, nullable: true),
      PropSpec(name: 'padding', type: PropType.edgeInsets, nullable: true),
      PropSpec(
        name: 'color',
        type: PropType.color,
        nullable: true,
        group: 'decoration',
      ),
      PropSpec(
        name: 'radius',
        type: PropType.borderRadius,
        nullable: true,
        group: 'decoration',
        arg: 'borderRadius',
      ),
    ],
  ),
  WidgetSpec(
    type: 'Padding',
    category: 'Layout',
    children: ChildrenMode.single,
    hasConstCtor: true,
    props: <PropSpec>[
      PropSpec(
        name: 'padding',
        type: PropType.edgeInsets,
        defaultValue: 12.0,
        required: true,
      ),
    ],
  ),
  WidgetSpec(
    type: 'Center',
    category: 'Layout',
    children: ChildrenMode.single,
    hasConstCtor: true,
  ),
  WidgetSpec(
    type: 'SizedBox',
    category: 'Layout',
    children: ChildrenMode.single,
    hasConstCtor: true,
    props: <PropSpec>[
      PropSpec(name: 'width', type: PropType.double, nullable: true),
      PropSpec(name: 'height', type: PropType.double, nullable: true),
    ],
  ),
  WidgetSpec(
    type: 'Card',
    category: 'Layout',
    children: ChildrenMode.single,
    hasConstCtor: true,
  ),

  // ————————————— 展示 —————————————
  WidgetSpec(
    type: 'Text',
    category: 'Display',
    children: ChildrenMode.none,
    hasConstCtor: true,
    positionalProp: 'data',
    props: <PropSpec>[
      PropSpec(
        name: 'data',
        type: PropType.string,
        defaultValue: 'Text',
        required: true,
      ),
      PropSpec(
        name: 'fontSize',
        type: PropType.double,
        nullable: true,
        group: 'style',
      ),
      PropSpec(
        name: 'color',
        type: PropType.color,
        nullable: true,
        group: 'style',
      ),
      PropSpec(
        name: 'bold',
        type: PropType.fontWeight,
        defaultValue: false,
        group: 'style',
        arg: 'fontWeight',
      ),
    ],
  ),
  WidgetSpec(
    type: 'Icon',
    category: 'Display',
    children: ChildrenMode.none,
    hasConstCtor: true,
    positionalProp: 'icon',
    props: <PropSpec>[
      PropSpec(
        name: 'icon',
        type: PropType.icon,
        defaultValue: 'add',
        required: true,
        values: kIconNames,
      ),
      PropSpec(name: 'size', type: PropType.double, nullable: true),
      PropSpec(name: 'color', type: PropType.color, nullable: true),
    ],
  ),
  WidgetSpec(
    type: 'Divider',
    category: 'Display',
    children: ChildrenMode.none,
    hasConstCtor: true,
    props: <PropSpec>[
      PropSpec(name: 'height', type: PropType.double, nullable: true),
      PropSpec(name: 'thickness', type: PropType.double, nullable: true),
      PropSpec(name: 'color', type: PropType.color, nullable: true),
    ],
  ),
  WidgetSpec(
    type: 'Image.network',
    category: 'Display',
    children: ChildrenMode.none,
    // Image.network 的构造器不是 const。
    hasConstCtor: false,
    positionalProp: 'src',
    props: <PropSpec>[
      PropSpec(
        name: 'src',
        type: PropType.string,
        defaultValue: 'https://picsum.photos/200',
        required: true,
      ),
      PropSpec(name: 'width', type: PropType.double, nullable: true),
      PropSpec(name: 'height', type: PropType.double, nullable: true),
      PropSpec(
        name: 'fit',
        type: PropType.enumValue,
        dartType: 'BoxFit',
        nullable: true,
        values: kBoxFit,
      ),
    ],
  ),
  WidgetSpec(
    type: 'Image.asset',
    category: 'Display',
    children: ChildrenMode.none,
    hasConstCtor: false,
    positionalProp: 'name',
    props: <PropSpec>[
      PropSpec(
        name: 'name',
        type: PropType.string,
        defaultValue: 'assets/image.png',
        required: true,
      ),
      PropSpec(name: 'width', type: PropType.double, nullable: true),
      PropSpec(name: 'height', type: PropType.double, nullable: true),
      PropSpec(
        name: 'fit',
        type: PropType.enumValue,
        dartType: 'BoxFit',
        nullable: true,
        values: kBoxFit,
      ),
    ],
  ),
  WidgetSpec(
    type: 'Image.file',
    category: 'Display',
    children: ChildrenMode.none,
    hasConstCtor: false,
    positionalProp: 'path',
    imports: <String>['dart:io'],
    props: <PropSpec>[
      PropSpec(
        name: 'path',
        type: PropType.filePath,
        defaultValue: '/tmp/image.png',
        required: true,
      ),
      PropSpec(name: 'width', type: PropType.double, nullable: true),
      PropSpec(name: 'height', type: PropType.double, nullable: true),
      PropSpec(
        name: 'fit',
        type: PropType.enumValue,
        dartType: 'BoxFit',
        nullable: true,
        values: kBoxFit,
      ),
    ],
  ),

  // ————————————— 输入 —————————————
  WidgetSpec(
    type: 'ElevatedButton',
    category: 'Input',
    children: ChildrenMode.none,
    hasConstCtor: true,
    callbackArg: 'onPressed',
    labelProp: 'label',
    props: <PropSpec>[
      PropSpec(
        name: 'label',
        type: PropType.string,
        defaultValue: '按钮',
        required: true,
      ),
      PropSpec(name: 'enabled', type: PropType.bool, defaultValue: true),
    ],
  ),
  WidgetSpec(
    type: 'IconButton',
    category: 'Input',
    children: ChildrenMode.none,
    hasConstCtor: true,
    callbackArg: 'onPressed',
    props: <PropSpec>[
      PropSpec(
        name: 'icon',
        type: PropType.iconWidget,
        defaultValue: 'add',
        required: true,
        values: kIconNames,
      ),
      PropSpec(
        name: 'size',
        type: PropType.double,
        nullable: true,
        arg: 'iconSize',
      ),
      PropSpec(name: 'color', type: PropType.color, nullable: true),
      PropSpec(name: 'enabled', type: PropType.bool, defaultValue: true),
    ],
  ),
  WidgetSpec(
    type: 'TextField',
    category: 'Input',
    children: ChildrenMode.none,
    hasConstCtor: true,
    props: <PropSpec>[
      PropSpec(
        name: 'hint',
        type: PropType.string,
        nullable: true,
        group: 'inputDecoration',
        arg: 'hintText',
      ),
      PropSpec(
        name: 'label',
        type: PropType.string,
        nullable: true,
        group: 'inputDecoration',
        arg: 'labelText',
      ),
    ],
  ),
  WidgetSpec(
    type: 'Checkbox',
    category: 'Input',
    children: ChildrenMode.none,
    hasConstCtor: true,
    callbackArg: 'onChanged',
    callbackParam: 'v',
    props: <PropSpec>[
      PropSpec(
        name: 'value',
        type: PropType.bool,
        defaultValue: false,
        required: true,
      ),
    ],
  ),
];

/// 按类型名索引的目录（O(1) 查找）。
final Map<String, WidgetSpec> kCatalogByType = <String, WidgetSpec>{
  for (final spec in kCatalog) spec.type: spec,
};

/// 取组件规格；未知类型返回 `null`。
WidgetSpec? specFor(String type) => kCatalogByType[type];
