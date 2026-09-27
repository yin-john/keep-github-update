/// 按平台文件名正则匹配 release 资产
library;

import '../config/models.dart';
import '../github/release_model.dart';

class MatchResult {
  const MatchResult(this.asset, this.rule);
  final Asset asset;
  final AssetRule rule;
}

/// 各平台在产物文件名中的特征关键字（用于排除它平台产物）
const Map<PlatformType, List<String>> _platformMarkers = {
  PlatformType.windows: ['windows', 'win32', 'win64', 'msvc'],
  PlatformType.linux: ['linux', 'appimage', 'ubuntu', 'debian'],
  PlatformType.android: ['android', 'apk'],
};

class AssetMatcher {
  /// 在当前平台下，按规则顺序返回第一个命中的资产。
  ///
  /// 规则：
  /// 1. 只使用 `platform == 目标平台` 的规则；
  /// 2. 名称带有「其它平台关键字」的资产会被排除，避免跨平台误选
  ///    （例如 Android 的宽松 `.*\\.zip` 规则不应抢走 `app-windows.zip`）；
  /// 3. [deviceArch] 非空（通常为 Android）时，优先选用与该架构一致的规则，
  ///    其次是 arch=any 的规则，最后才是其它架构规则；
  /// 4. 规则指定了具体架构时，优先选择文件名含该架构关键字的资产。
  MatchResult? match(Release release, PlatformType platform,
      List<AssetRule> rules, [TargetArch? deviceArch]) {
    final candidates = rules.where((r) => r.platform == platform).toList();

    List<AssetRule> ordered;
    if (deviceArch != null && deviceArch != TargetArch.any) {
      ordered = [
        ...candidates.where((r) => r.arch == deviceArch),
        ...candidates.where((r) => r.arch == TargetArch.any),
        ...candidates.where(
            (r) => r.arch != deviceArch && r.arch != TargetArch.any),
      ];
    } else {
      ordered = candidates;
    }

    for (final rule in ordered) {
      final result = _matchRule(release, rule, platform);
      if (result != null) return result;
    }
    return null;
  }

  MatchResult? _matchRule(Release release, AssetRule rule, PlatformType platform) {
    final re = _tryRegex(rule.nameRegex);
    if (re == null) return null;
    final matched = release.assets
        .where((a) => !_isForeign(a.name, platform) && re.hasMatch(a.name))
        .toList();
    if (matched.isEmpty) return null;

    // 规则指定架构时，优先选名称含该架构关键字的资产
    if (rule.arch != TargetArch.any) {
      final tokens = rule.arch.tokens;
      final hit = matched.firstWhere(
        (a) => tokens.any((t) => a.name.toLowerCase().contains(t)),
        orElse: () => matched.first,
      );
      return MatchResult(hit, rule);
    }
    return MatchResult(matched.first, rule);
  }

  /// 名称是否带有「其它平台」的关键字
  bool _isForeign(String name, PlatformType target) {
    final lower = name.toLowerCase();
    for (final entry in _platformMarkers.entries) {
      if (entry.key == target) continue;
      if (entry.value.any(lower.contains)) return true;
    }
    return false;
  }

  RegExp? _tryRegex(String pattern) {
    try {
      return RegExp(pattern, caseSensitive: false);
    } catch (_) {
      return null; // 非法正则忽略该规则
    }
  }

  /// 列出所有平台的命中（用于调试/展示）
  List<MatchResult> matchAll(Release release, List<AssetRule> rules) {
    final out = <MatchResult>[];
    for (final p in PlatformType.values) {
      final m = match(release, p, rules);
      if (m != null) out.add(m);
    }
    return out;
  }
}
