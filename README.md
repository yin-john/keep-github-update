# GRKU · GitHub Releases Keep Update

自动追踪 GitHub Release，检测到新版本后按**平台 + 策略**下载并安装的跨平台工具。
同一套核心逻辑提供 **GUI（Flutter）**、**CLI** 与 **TUI** 三种界面。

## 功能

- **多平台更新策略**
  - Windows：Portable（zip/7z 解压覆盖、或**单文件 exe** 直接替换）、Installer（msi / setup.exe 静默安装）
  - Linux：Portable（tar.gz、**单文件 AppImage**）、Docker（拉取镜像并重建容器）
  - Android：APK 安装（root / Shizuku 静默安装，或**系统安装器**普通安装）、Magisk / KernelSU 模块刷入
- **已装版本识别**：读取设备上真实安装的版本（Android 应用 versionName、Magisk 模块 `module.prop`、便携目录的版本记录文件），无 v 前缀等写法差异也能正确比对
- **签名一致性校验**：Android 安装前比对 APK 与已装应用签名；可开启「无视签名强制安装」（`pm uninstall -k` 保留应用数据后重装）
- **下载**：多线程分块 + 断点续传，可中断/暂停；镜像改写加速；可选校验和（sha256/md5）
- **安装重试**：下载成功但安装失败时，可仅重试安装而无需重新下载
- **规则库**：按 Windows / Linux / Android 三系统提供预设匹配规则，粘贴 GitHub 链接即自动解析 owner/repo
- **数据保护**：portable 覆盖更新时可指定需保留的**数据目录**与**数据文件**（支持多条正则）
- **通知**：系统通知 + Webhook（可选触发事件）
- **Android 权限管理**：存储（所有文件访问）、通知、root、Shizuku 的检测与申请

## 构建

```bash
flutter pub get

# Windows GUI
flutter build windows --release

# CLI / TUI（单文件可执行）
dart compile exe bin/grku.dart -o build/grku.exe

# Android（分 ABI + 通用包）
flutter build apk --release --split-per-abi
flutter build apk --release
```

## 使用

```bash
# GUI
build/windows/x64/runner/Release/github_releases_keep_update.exe

# CLI
grku list                     # 列出仓库
grku check                    # 检测可更新项
grku update                   # 下载并安装
grku retry                    # 仅重试安装（复用已下载文件）
grku add --platform windows --repo owner/repo --strategy portable --regex ".*windows.*\.zip$"
grku config import <file>     # 导入配置（空配置会被拦下）
grku config export <file>     # 导出配置
grku tui                      # 交互式终端界面
```

配置为 YAML/JSON，带 `configVersion` 字段（旧配置缺省按 1 处理）；示例见 `example_config.yaml`。

## 目录结构

```
lib/
  core/       配置模型与仓储、GitHub API、资产匹配、下载、更新编排、版本比对、平台桥接
  platforms/  Windows / Linux / Android 更新器装配与原生能力（Android MethodChannel）
  ui/         Flutter GUI（仓库列表、下载、设置）
  tui/        终端交互界面
  cli/        命令行入口与子命令
test/         单元测试（版本比对、签名校验、配置读写、下载、更新编排等）
vendor/win32  为兼容 Windows 工具链本地化的 win32 包（由 dependency_overrides 指向）
```

## 说明

- Android 端部分能力（权限申请、签名读取、系统安装器）通过 `MethodChannel`（`grku/native`）调用原生实现，见 `android/app/src/main/kotlin/.../MainActivity.kt`
- 日志默认写在用户可访问路径（Android 为 `<外部存储>/grku/logs/app.log`），无写入权限时自动回退到应用私有目录
