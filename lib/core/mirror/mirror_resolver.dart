/// 镜像地址解析：支持前缀替换（prefix）与正则改写（regex）。
library;

import '../config/models.dart';

class MirrorResolver {

  const MirrorResolver(this.mirrors);
  final List<MirrorConfig> mirrors;

  /// 将 github.com 资源地址按镜像规则改写；可叠加多条规则。
  ///
  /// 未填写完整的镜像（pattern/replacement 为空）会被跳过，
  /// 以免把正常的下载地址改写成无效地址。
  String resolve(String url) {
    var out = url;
    for (final m in mirrors) {
      if (m.pattern.isEmpty) continue; // 未填写匹配规则：跳过
      if (m.mode == MirrorMode.prefix) {
        if (m.replacement.isEmpty) continue; // 前缀模式未填替换：跳过
        if (out.startsWith(m.pattern)) {
          out = m.replacement + out.substring(m.pattern.length);
        }
      } else {
        try {
          out = out.replaceAll(RegExp(m.pattern), m.replacement);
        } catch (_) {
          // 非法正则忽略
        }
      }
    }
    return out;
  }
}
