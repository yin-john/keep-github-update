# 07 · CLI 与 TUI

[← 返回目录](README.md)

## CLI（`bin/grku.dart` → `lib/cli/`）

编译为单文件可执行（CI 注入版本号）：

```bash
dart compile exe bin/grku.dart -o build/grku.exe \
  --define=GRKU_VERSION=<pubspec 版本>
```

### 子命令

| 命令 | 说明 |
|---|---|
| `grku list` | 列出仓库及已装/最新版本 |
| `grku check` | 检测可更新项 |
| `grku update` | 下载并安装（可带仓库过滤） |
| `grku retry` | 仅重试安装（复用已下载文件） |
| `grku add` | 添加仓库（`--platform` `--repo` `--strategy` `--regex` 等） |
| `grku config import/export <file>` | 导入（空配置会被拦下）/ 导出配置 |
| `grku tui` | 进入交互式终端界面 |

### 上下文（`lib/cli/app_context.dart`）

- 配置路径：`GRKU_CONFIG` 环境变量优先，否则默认路径（与 GUI 同一套 `app_paths.dart`）。
- Android 上 CLI 只有 `ShellAndroidEnv`（root / Shizuku shell），没有 MethodChannel 能力——静默安装、图标提取等能力受限是设计使然。

## TUI（`lib/tui/tui_app.dart`）

基于 `dart_console2` 的交互式终端界面：

- 仓库列表：状态着色（可更新绿 / 已最新琥珀 / 未知灰），显示已装/最新版本；
- 仓库详情：含通知开关（`notificationsEnabled` 切换）等；
- 操作：检测 / 更新 / 重试安装，与 GUI 共用 `UpdateService` 与配置读写；
- 键盘导航，`q` 退出。

## 与 GUI 的关系

三种界面共享：

- 同一套配置文件与 `ConfigRepository`；
- 同一个 `UpdateService`（经 `createUpdateServiceForCurrentPlatform` 装配）；
- 同样的版本比较、匹配、下载逻辑。

差异仅在「能力入口」：GUI 用 MethodChannel + 系统 API，CLI/TUI 用 shell（root/Shizuku）。
