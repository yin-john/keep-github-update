/// 把值格式化成 Dart 源码字面量（纯 Dart，不依赖 Flutter）。
///
/// 所有函数都只产出**源文本**，不构造任何 Flutter 对象——本工具跑在 `dart run`
/// 下，没有 `dart:ui`。
library;

/// 把任意字符串转成单引号 Dart 字符串字面量，**永不插值**。
///
/// `'`、`\`、`$` 与控制字符都会被转义，因此调用方无需关心内容。
String dartString(String value) {
  final buffer = StringBuffer("'");
  for (final rune in value.runes) {
    final escaped = switch (rune) {
      0x5C => r'\\',
      0x27 => r"\'",
      0x24 => r'\$',
      0x0A => r'\n',
      0x0D => r'\r',
      0x09 => r'\t',
      _ => null,
    };
    if (escaped != null) {
      buffer.write(escaped);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  buffer.write("'");
  return buffer.toString();
}

/// 把数字格式化成 `double` 字面量（整数值补 `.0`，避免 `double?` 槽位类型错误）。
String dartDouble(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return '${value.toInt()}.0';
  }
  return value.toString();
}

/// `#RRGGBB` / `#AARRGGBB` → `Color(0x…)`。
String dartColor(String hex) {
  var cleaned = hex.trim().toUpperCase();
  if (cleaned.startsWith('#')) {
    cleaned = cleaned.substring(1);
  }
  if (cleaned.length == 6) {
    cleaned = 'FF$cleaned';
  }
  if (!RegExp(r'^[0-9A-F]{8}$').hasMatch(cleaned)) {
    throw ArgumentError('非法颜色值：$hex（应为 #RRGGBB 或 #AARRGGBB）');
  }
  return 'Color(0x$cleaned)';
}

/// 图标名 → `Icons.<name>`；名必须是合法小写标识符。
String dartIcon(String name) {
  if (!RegExp(r'^[a-z][A-Za-z0-9_]*$').hasMatch(name)) {
    throw ArgumentError('非法图标名：$name');
  }
  return 'Icons.$name';
}

/// 枚举值 → `<EnumType>.<value>`（如 `MainAxisAlignment.center`）。
String dartEnum(String dartType, String value) {
  if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(value)) {
    throw ArgumentError('非法枚举值：$value');
  }
  return '$dartType.$value';
}

/// `12` → `EdgeInsets.all(12.0)`。
String dartEdgeInsetsAll(double value) =>
    'EdgeInsets.all(${dartDouble(value)})';

/// `12` → `BorderRadius.circular(12.0)`。
///
/// 注意：`BorderRadius.circular` 是**工厂构造器**，不能用于 const 上下文。
String dartBorderRadiusCircular(double value) =>
    'BorderRadius.circular(${dartDouble(value)})';
