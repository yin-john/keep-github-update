import 'models.dart';

/// 设置页的草稿状态：所有修改先存在内存中，点「保存」后才写入真实配置。
///
/// 用法：
/// - UI 控件统一通过 [patch] 修改草稿（[dirty] 变为 true，但不影响 provider）；
/// - 返回/放弃修改时用 [reset] 丢弃草稿；
/// - 保存时用 [commitTo] 以 provider 最新配置为底生成最终配置
///   （保留其 `repos`，防止设置页停留期间仓库列表被并发修改所覆盖）。
class SettingsDraft {
  SettingsDraft(AppConfig initial) : _value = initial;

  AppConfig _value;
  bool _dirty = false;

  /// 当前草稿（UI 显示值）
  AppConfig get value => _value;

  /// 是否有未保存的修改
  bool get dirty => _dirty;

  /// 以草稿为底做增量修改，并标记为未保存
  void patch(AppConfig Function(AppConfig base) f) {
    _value = f(_value);
    _dirty = true;
  }

  /// 丢弃草稿，重置为 [base]（导入配置 / 配置被外部重载后调用）
  void reset(AppConfig base) {
    _value = base;
    _dirty = false;
  }

  /// 生成最终要提交的配置：软件设置取草稿，`repos` 取 [latest]（provider 最新值）
  AppConfig commitTo(AppConfig latest) => _value.copyWith(repos: latest.repos);
}
