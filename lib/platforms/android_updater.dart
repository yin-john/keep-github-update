/// Android 更新器：Magisk/KernelSU 模块刷入 + APK 安装（安装前校验签名一致性）
library;

import '../core/config/models.dart';
import '../core/github/release_model.dart';
import '../core/log/app_log.dart';
import '../core/platform/android_env.dart';
import '../core/platform/bridge.dart';
import '../core/platform/signature_check.dart';
import '../core/updater/updater.dart';

class AndroidUpdater implements Updater {

  const AndroidUpdater(this.bridge,
      [this.defaultMethod = InstallMethod.root,
      this.env,
      this.ignoreSignature = false]);
  final PlatformBridge bridge;
  final InstallMethod defaultMethod;

  /// 设备能力（读取 APK / 已安装应用的签名与包名），为空时跳过签名校验
  final AndroidEnv? env;

  /// 签名不一致时是否强制安装（需 root，会先卸载原应用）
  final bool ignoreSignature;

  @override
  bool isApplicable(PlatformType p, UpdateStrategy s) =>
      p == PlatformType.android &&
      (s == UpdateStrategy.module || s == UpdateStrategy.apk);

  @override
  Future<void> apply({
    required Asset asset,
    required String localPath,
    required RepoConfig repo,
    required AssetRule rule,
  }) async {
    switch (rule.strategy) {
      case UpdateStrategy.module:
        await bridge.flashModule(localPath);
      case UpdateStrategy.apk:
        await _installApk(repo, localPath);
      default:
        throw Exception('Android 不支持的策略: ${rule.strategy}');
    }
  }

  /// 安装前校验签名：不一致时按配置拒绝安装，或（强制模式）先卸载再装
  Future<void> _installApk(RepoConfig repo, String apkPath) async {
    final method = repo.apkInstallMethod ?? defaultMethod;
    final e = env;
    if (e != null && e.isAndroid) {
      final configured = repo.packageName;
      final pkg = (configured != null && configured.isNotEmpty)
          ? configured
          : (await e.apkPackageName(apkPath) ?? '');
      if (pkg.isEmpty) {
        AppLog.warn('无法确定目标包名，跳过签名校验（由系统在安装时校验）');
      } else {
        final installedSig = await e.installedSignature(pkg);
        final apkSig = await e.apkSignature(apkPath);
        final verdict = evaluateApkSignature(
          installedExists: installedSig != null && installedSig.isNotEmpty,
          installedSignature: installedSig,
          apkSignature: apkSig,
        );
        AppLog.info('签名校验 $pkg → ${verdict.name}');
        if (!canProceedWithInstall(verdict,
            ignoreSignature: ignoreSignature)) {
          throw Exception(signatureVerdictMessage(verdict, packageName: pkg));
        }
        if (needsUninstallFirst(verdict, ignoreSignature: ignoreSignature) &&
            method != InstallMethod.normal) {
          // 用 -k 卸载：保留应用数据，重装后仍可用
          AppLog.warn('签名不一致，按设置强制安装：先卸载 $pkg（保留应用数据）');
          await bridge.uninstallApk(pkg, keepData: true);
        }
      }
    }

    if (method == InstallMethod.normal) {
      final ok = await e?.installWithSystem(apkPath) ?? false;
      if (!ok) {
        throw Exception('无法调起系统安装器：请确认应用内已允许「安装未知应用」，'
            '或在设置中选择 root / Shizuku 方式安装');
      }
      AppLog.info('已调起系统安装器（需在弹窗中手动确认）');
      return;
    }
    await bridge.installApk(apkPath, method: method);
  }
}
