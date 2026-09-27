/// 仓库显示名称解析（纯逻辑，便于单元测试）。
///
/// 列表中的显示规则：
/// - 有「自定义名称」或「自动获取到的软件名称」时：
///   主标题=该名称，副标题=「作者/仓库名」（以次一级字体显示在下一行）；
/// - 都没有（或与「作者/仓库名」相同）时：只显示「作者/仓库名」。
library;

/// 列表标题的两行内容
class RepoTitle {
  const RepoTitle({required this.primary, this.secondary});

  /// 主标题（较大字体）
  final String primary;

  /// 副标题：非空时以次一级字体显示在下一行
  final String? secondary;

  bool get hasSecondary => secondary != null && secondary!.isNotEmpty;

  @override
  String toString() =>
      hasSecondary ? '$primary ($secondary)' : primary;
}

/// 解析仓库在列表中的标题
RepoTitle resolveRepoTitle({
  required String fullName,
  String? displayName,
  String? apkLabel,
}) {
  final custom = displayName?.trim() ?? '';
  final auto = apkLabel?.trim() ?? '';
  final name = custom.isNotEmpty ? custom : auto;
  if (name.isEmpty || name == fullName) {
    return RepoTitle(primary: fullName);
  }
  return RepoTitle(primary: name, secondary: fullName);
}

/// 是否使用了自定义名称（非空且与作者/仓库名不同）
bool hasCustomName(String? displayName, String fullName) {
  final v = displayName?.trim() ?? '';
  return v.isNotEmpty && v != fullName;
}
