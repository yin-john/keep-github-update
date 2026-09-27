import 'package:flutter_test/flutter_test.dart';
import 'package:github_releases_keep_update/core/config/models.dart';
import 'package:github_releases_keep_update/core/download/checksum.dart';
import 'package:github_releases_keep_update/core/github/release_model.dart';

Release _release() => const Release(
      tagName: 'v1.0.0',
      name: 'v1.0.0',
      prerelease: false,
      htmlUrl: '',
      assets: [
        Asset(
            name: 'app.zip',
            browserDownloadUrl: 'https://github.com/o/r/releases/download/v1/app.zip',
            size: 1),
        Asset(
            name: 'app.zip.sha256',
            browserDownloadUrl: 'https://github.com/o/r/releases/download/v1/app.zip.sha256',
            size: 1),
        Asset(
            name: 'app.zip.md5',
            browserDownloadUrl: 'https://github.com/o/r/releases/download/v1/app.zip.md5',
            size: 1),
        Asset(
            name: 'sha256sums.txt',
            browserDownloadUrl: 'https://github.com/o/r/releases/download/v1/sha256sums.txt',
            size: 1),
      ],
    );

void main() {
  final target = _release().assets.first; // app.zip
  const ruleSha = AssetRule(
      platform: PlatformType.windows,
      strategy: UpdateStrategy.portable,
      nameRegex: '.*',
      verifyChecksum: true,
      checksumType: ChecksumType.sha256);
  final ruleMd5 = ruleSha.copyWithCompat(checksumType: ChecksumType.md5);

  test('默认扩展名定位 sha256 校验文件', () {
    final cs = findChecksumAsset(_release(), target, ruleSha);
    expect(cs?.name, 'app.zip.sha256');
  });

  test('默认扩展名定位 md5 校验文件', () {
    final cs = findChecksumAsset(_release(), target, ruleMd5);
    expect(cs?.name, 'app.zip.md5');
  });

  test('自定义正则定位 sha256sums.txt', () {
    final rule = ruleSha.copyWithCompat(checksumRegex: r'.*sha256sums.*\.txt$');
    final cs = findChecksumAsset(_release(), target, rule);
    expect(cs?.name, 'sha256sums.txt');
  });

  test('解析 <hash>  <filename> 格式', () {
    final hex = '0123456789abcdef' * 4; // 64 位
    final parsed = parseChecksum('$hex  app.zip', ChecksumType.sha256);
    expect(parsed, hex);
  });

  test('解析 <hash> *<filename> 与大小写归一', () {
    const mixed = 'AbCdEf0123456789aBcDeF0123456789AbCdEf0123456789aBcDeF0123456789';
    final lower = mixed.toLowerCase();
    final parsed = parseChecksum('$mixed *app.zip', ChecksumType.sha256);
    expect(parsed, lower);
  });

  test('md5 长度解析', () {
    const hex32 = '0123456789abcdef0123456789abcdef';
    final parsed = parseChecksum('$hex32  app.zip', ChecksumType.md5);
    expect(parsed, hex32);
  });
}

extension _AssetRuleCompat on AssetRule {
  AssetRule copyWithCompat({
    ChecksumType? checksumType,
    String? checksumRegex,
  }) =>
      AssetRule(
        platform: platform,
        strategy: strategy,
        nameRegex: nameRegex,
        checksumRegex: checksumRegex ?? this.checksumRegex,
        verifyChecksum: verifyChecksum,
        checksumType: checksumType ?? this.checksumType,
      );
}
