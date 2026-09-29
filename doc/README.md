# GRKU 代码文档

> GRKU · GitHub Releases Keep Update —— 自动追踪 GitHub Release 并按平台策略下载安装的跨平台工具（GUI / CLI / TUI）。

## 目录

1. [架构总览](01-架构总览.md) —— 分层设计、模块地图、一次更新的完整数据流
2. [配置体系](02-配置体系.md) —— config.yaml / repos.yaml（v4 拆分与迁移）、路径策略、设置页草稿机制
3. [GitHub 与资产匹配](03-GitHub与资产匹配.md) —— Release 获取、镜像改写、匹配规则、版本比对
4. [下载与更新编排](04-下载与更新编排.md) —— 下载管理、更新编排、已装版本识别、APK 信息提取与仓库分类
5. [平台实现](05-平台实现.md) —— 平台桥接、Android 原生层（MethodChannel）、Windows / Linux 更新器
6. [GUI 界面](06-GUI界面.md) —— 页面结构、状态管理（Riverpod）、关键交互
7. [CLI 与 TUI](07-CLI与TUI.md) —— 命令行子命令与终端交互界面
8. [测试与 CI 发布](08-测试与CI发布.md) —— 单元测试布局、CI 工作流、版本与发版规则

## 快速导航

| 主题 | 位置 |
|---|---|
| 核心模型（AppConfig / RepoConfig / AssetRule） | `lib/core/config/models.dart` |
| 更新编排（检测 / 下载 / 安装） | `lib/core/updater/update_service.dart` |
| 下载管理（多线程 / 断点续传） | `lib/core/download/download_manager.dart` |
| Android 原生能力 | `android/app/src/main/kotlin/.../MainActivity.kt` |
| GUI 页面 | `lib/ui/screens/` |
| 单元测试 | `test/` |
| CI 工作流 | `.github/workflows/ci.yml` |

## 阅读建议

- **想理解一次更新是怎么跑通的**：先读 [架构总览](01-架构总览.md) 的数据流，再读 [下载与更新编排](04-下载与更新编排.md)。
- **想加一个设置项**：读 [配置体系](02-配置体系.md) 与 [GUI 界面](06-GUI界面.md) 的设置页草稿机制。
- **想支持新的安装方式**：读 [平台实现](05-平台实现.md) 与 [GitHub 与资产匹配](03-GitHub与资产匹配.md) 的策略枚举。
