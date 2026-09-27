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
String signatureVerdictMessage(ApkSignatureVerdict v, {String packageName = ''}) {
  final pkg = packageName.isEmpty ? '目标应用' : packageName;
  switch (v) {
    case ApkSignatureVerdict.match:
      return '$pkg 签名一致，可安全覆盖安装';
    case ApkSignatureVerdict.mismatch:
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

/// 依据结论与「无视签名」开关，判断是否可以继续安装
bool canProceedWithInstall(
  ApkSignatureVerdict v, {
  required bool ignoreSignature,
}) {
  if (v != ApkSignatureVerdict.mismatch) return true;
  return ignoreSignature;
}

/// 签名不一致且开启强制安装时，需要先卸载原应用（普通 pm install -r 会失败）
bool needsUninstallFirst(
  ApkSignatureVerdict v, {
  required bool ignoreSignature,
}) =>
    v == ApkSignatureVerdict.mismatch && ignoreSignature;
