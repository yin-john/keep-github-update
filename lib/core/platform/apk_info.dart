/// APK 的软件名称、包名、版本与图标信息（Android：从下载到的 APK 中读取）。
library;

class ApkAppInfo {
  const ApkAppInfo({
    this.label,
    this.iconPath,
    this.packageName,
    this.version,
    this.xposed = false,
  });

  factory ApkAppInfo.fromChannel(Object? raw) {
    if (raw is! Map) return const ApkAppInfo();
    String? pick(String key) {
      final v = raw[key];
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    final x = raw['xposed'];
    final xposed = x == true || x?.toString().trim() == 'true';
    return ApkAppInfo(
      label: pick('label'),
      iconPath: pick('iconPath'),
      packageName: pick('packageName'),
      version: pick('version'),
      xposed: xposed,
    );
  }

  /// 软件名称（应用标签），读不到为 null
  final String? label;

  /// 图标文件（PNG）的绝对路径，读不到为 null
  final String? iconPath;

  /// APK 的包名，读不到为 null
  final String? packageName;

  /// APK 的 versionName，读不到为 null
  final String? version;

  /// 是否声明 xposedmodule 元数据（XP/LSPosed 模块）
  final bool xposed;

  bool get isEmpty =>
      label == null &&
      iconPath == null &&
      packageName == null &&
      version == null;

  bool get isNotEmpty => !isEmpty;

  @override
  String toString() => 'ApkAppInfo(label: $label, packageName: $packageName, '
      'version: $version, iconPath: $iconPath, xposed: $xposed)';
}
