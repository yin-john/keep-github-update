import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/platform/signature_check.dart';

void main() {
  group('APK 签名一致性判定', () {
    test('未安装视为全新安装', () {
      expect(
        evaluateApkSignature(
            installedExists: false,
            installedSignature: null,
            apkSignature: 'ab'),
        ApkSignatureVerdict.notInstalled,
      );
    });

    test('签名一致（忽略大小写）', () {
      expect(
        evaluateApkSignature(
            installedExists: true,
            installedSignature: 'AABBCC',
            apkSignature: 'aabbcc'),
        ApkSignatureVerdict.match,
      );
    });

    test('签名不一致', () {
      expect(
        evaluateApkSignature(
            installedExists: true,
            installedSignature: 'aabbcc',
            apkSignature: 'ddeeff'),
        ApkSignatureVerdict.mismatch,
      );
    });

    test('信息缺失时交给系统判断', () {
      expect(
        evaluateApkSignature(
            installedExists: true, installedSignature: null, apkSignature: 'x'),
        ApkSignatureVerdict.unknown,
      );
      expect(
        evaluateApkSignature(
            installedExists: true, installedSignature: 'x', apkSignature: ''),
        ApkSignatureVerdict.unknown,
      );
    });
  });

  group('是否允许继续安装', () {
    test('一致 / 新装 / 未知都允许', () {
      expect(
          canProceedWithInstall(ApkSignatureVerdict.match,
              ignoreSignature: false),
          isTrue);
      expect(
          canProceedWithInstall(ApkSignatureVerdict.notInstalled,
              ignoreSignature: false),
          isTrue);
      expect(
          canProceedWithInstall(ApkSignatureVerdict.unknown,
              ignoreSignature: false),
          isTrue);
    });

    test('不一致时默认拒绝，开启强制安装后放行', () {
      expect(
          canProceedWithInstall(ApkSignatureVerdict.mismatch,
              ignoreSignature: false),
          isFalse);
      expect(
          canProceedWithInstall(ApkSignatureVerdict.mismatch,
              ignoreSignature: true),
          isTrue);
    });

    test('强制安装需先卸载原应用', () {
      expect(
          needsUninstallFirst(ApkSignatureVerdict.mismatch,
              ignoreSignature: true),
          isTrue);
      expect(
          needsUninstallFirst(ApkSignatureVerdict.mismatch,
              ignoreSignature: false),
          isFalse);
      expect(
          needsUninstallFirst(ApkSignatureVerdict.match, ignoreSignature: true),
          isFalse);
    });
  });

  test('提示文案包含处理方式', () {
    final msg = signatureVerdictMessage(ApkSignatureVerdict.mismatch,
        packageName: 'com.foo');
    expect(msg, contains('com.foo'));
    expect(msg, contains('无视签名强制安装'));
    expect(
      signatureVerdictMessage(ApkSignatureVerdict.notInstalled,
          packageName: 'com.foo'),
      contains('全新安装'),
    );
  });
}
