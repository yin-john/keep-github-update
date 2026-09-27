# GRKU · GitHub Releases Keep Update

自动追踪 GitHub Release，检测到新版本后按**平台 + 策略**下载并安装的跨平台工具。
同一套核心逻辑提供 **GUI（Flutter）**、**CLI** 与 **TUI** 三种界面。

## 功能
当前已实现windows和Android双平台
- **多平台更新策略**
  - Windows：Portable（zip/7z 解压覆盖（可排除配置文件）、或**单文件 exe** 直接替换）、Installer（msi / setup.exe 静默安装）
  - Linux：Portable（tar.gz、**单文件 AppImage**）、Docker（拉取镜像并重建容器）
  - Android：APK 安装（root / Shizuku 静默安装，或**系统安装器**普通安装）、Magisk / KernelSU 模块刷入
- **已装版本识别**：读取设备上真实安装的版本（Android 应用 versionName、Magisk 模块 `module.prop`、便携目录的版本记录文件），无 v 前缀等写法差异也能正确比对
- **签名一致性校验**：Android 安装前比对 APK 与已装应用签名；可开启「无视签名强制安装」（`pm uninstall -k` 保留应用数据后重装）
- **下载**：多线程分块 + 断点续传，可中断/暂停；镜像改写加速；可选校验和（sha256/md5）
- **安装重试**：下载成功但安装失败时，可仅重试安装而无需重新下载
- **规则库**：按 Windows / Linux / Android 三系统提供预设匹配规则，粘贴 GitHub 链接即自动解析 owner/repo
- **数据保护**：portable 覆盖更新时可指定需保留的**数据目录**与**数据文件**（支持多条正则）
- **通知**：系统通知 + Webhook（可选触发事件）
- **后台自动检测**：全局检测间隔（默认 6 小时）可在设置中调整，单个仓库可单独覆盖或关闭；检测到新版本时发系统通知
- **后台保活 + 常驻通知栏**：Android 用原生前台服务（常驻通知，进程保活，通知中显示下次检测时间）；Windows / Linux 开启后关闭窗口不退出，继续按间隔检测
- **仓库展示**：可为仓库设置**自定义显示名称**；Android 可选择「下载 APK 后自动获取图标与软件名称」，**优先复用本地已下载的 APK**，图标保存为下载目录下的 `app_icon.png`、名称/包名/版本写入 `app_name.txt`；列表中图标 + 主标题为该名称（自定义名称优先，其次为获取到的软件名）、「作者/仓库名」以次一级字体显示在下一行，并显示**已下载版本 / 已安装版本**；未设置名称则只显示作者/仓库名
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

配置分为两个文件：**软件配置** `config.yaml` 与**仓库配置** `repos.yaml`（同目录、均为 `configVersion: 4`）。旧版单文件配置（v1–v3）在每次启动时自动检测并转换，原文件备份为 `config.yaml.bak`；导入/导出仍是单个合并文件，便于分享。示例见 `example_config.yaml`。

## 开发流程（CI 在 GitHub 上跑）

分析与测试都由 GitHub Actions 负责，本地不必执行 `flutter analyze` / `flutter test`：

1. 改动推到分支并开 PR：CI 只跑「静态分析（零容忍）+ 单元测试」；
2. 检查通过后合并到 `main`：CI 自动构建 Windows GUI / CLI 与 Android 的分 ABI + 通用包；
3. 构建成功且配置了签名密钥时会按 `pubspec.yaml` 的版本号自动创建 Release（同一版本已存在则跳过，可先删旧 Release 再重发）。

本地排查失败时可用 `gh` 读取日志：

```bash
gh pr checks                 # 查看当前 PR 的检查结果
gh run list --limit 5        # 最近的运行
gh run view <run-id> --log-failed   # 只看失败步骤的日志
```

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
