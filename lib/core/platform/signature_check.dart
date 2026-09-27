/// APK 签名一致性判定（纯逻辑，便于单元测试）。
library;

/// 签名比对结论
enum ApkSignatureVerdict {
  /// 已安装版本与待安装 APK 签名一致
  match,

  /// 签名不一致：直接覆盖安装会被系统拒绝
  mismatch,

  /// 目标应用尚未安装，属全新安装
  notInstalled,

  /// 读不到签名信息（无权限 / 非 APK），交由系统在安装时判断
  unknown,
}

/// 人工可读的结论说明
///
/// [isSelf] 表示待安装的目标就是本应用自身（自更新）。
String signatureVerdictMessage(ApkSignatureVerdict v,
    {String packageName = '', bool isSelf = false}) {
  final pkg = packageName.isEmpty ? '目标应用' : packageName;
  switch (v) {
    case ApkSignatureVerdict.match:
      return '$pkg 签名一致，可安全覆盖安装';
    case ApkSignatureVerdict.mismatch:
      if (isSelf) {
        return '$pkg 是本应用自身，但新版本 APK 与已安装版本的签名不一致。\n'
            '为避免把正在运行的自己卸载掉，已中止安装（不会卸载本应用）。\n'
            '请改用与已安装版本相同签名的构建；若必须更换签名，'
            '请先在「设置」导出配置，再手动卸载本应用后安装新包。';
      }
      return '$pkg 的签名与已安装版本不一致，覆盖安装会被系统拒绝。\n'
          '若确认该安装包来源可信，可在「设置 → Android 权限」开启「无视签名强制安装」'
          '（需 root）：会先 `pm uninstall -k` 卸载但保留应用数据，再安装新包。';
    case ApkSignatureVerdict.notInstalled:
      return '$pkg 尚未安装，将全新安装';
    case ApkSignatureVerdict.unknown:
      return '未能读取 $pkg 的签名信息，将由系统在安装时校验';
  }
}

/// 比对签名（大小写不敏感）
ApkSignatureVerdict evaluateApkSignature({
  required bool installedExists,
  String? installedSignature,
  String? apkSignature,
}) {
  if (!installedExists) return ApkSignatureVerdict.notInstalled;
  final a = installedSignature?.trim().toLowerCase();
  final b = apkSignature?.trim().toLowerCase();
  if (a == null || a.isEmpty || b == null || b.isEmpty) {
    return ApkSignatureVerdict.unknown;
  }
  return a == b ? ApkSignatureVerdict.match : ApkSignatureVerdict.mismatch;
}

/// 依据结论与「无视签名」开关，判断是否可以继续安装。
///
/// [isSelf] 表示待安装的是本应用自身：签名不一致时一律拒绝——
/// 强制安装需要先卸载目标应用，那会把运行中的自己直接删掉。
bool canProceedWithInstall(
  ApkSignatureVerdict v, {
  required bool ignoreSignature,
  bool isSelf = false,
}) {
  if (v != ApkSignatureVerdict.mismatch) return true;
  if (isSelf) return false;
  return ignoreSignature;
}

/// 签名不一致且开启强制安装时，需要先卸载原应用（普通 pm install -r 会失败）。
///
/// **自身应用永不卸载**：卸载自己会让运行中的应用直接消失，安装也无从继续。
bool needsUninstallFirst(
  ApkSignatureVerdict v, {
  required bool ignoreSignature,
  bool isSelf = false,
}) =>
    v == ApkSignatureVerdict.mismatch && ignoreSignature && !isSelf;

/// 安装前应执行的动作
enum ApkInstallAction {
  /// 直接（覆盖）安装
  install,

  /// 先卸载原应用（保留数据）再安装
  uninstallThenInstall,

  /// 拒绝安装
  reject,
}

/// 综合签名结论、「无视签名」开关与是否自身应用，决定安装动作
ApkInstallAction planApkInstall({
  required ApkSignatureVerdict verdict,
  required bool ignoreSignature,
  bool isSelf = false,
}) {
  if (!canProceedWithInstall(verdict,
      ignoreSignature: ignoreSignature, isSelf: isSelf)) {
    return ApkInstallAction.reject;
  }
  if (needsUninstallFirst(verdict,
      ignoreSignature: ignoreSignature, isSelf: isSelf)) {
    return ApkInstallAction.uninstallThenInstall;
  }
  return ApkInstallAction.install;
}
