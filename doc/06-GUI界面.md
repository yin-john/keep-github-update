# 06 · GUI 界面

[← 返回目录](README.md)

## 应用壳与导航（`lib/app.dart`）

- 监听 `configProvider`：`checkIntervalMinutes` 变化时重排后台调度，`backgroundKeepAlive` 决定保活。
- 页面：仓库列表（首页）/ 下载 / 设置；Android 端另有原生前台服务与常驻通知。

## 状态管理（`lib/ui/providers/`）

| Provider | 说明 |
|---|---|
| `configProvider` | `StateNotifierProvider<ConfigNotifier, AppConfig>`；`setConfig` / `updateRepo` / `reload` / `freshRepo`（取最新仓库条目，防旧快照覆盖） |
| `configRepoProvider` | `ConfigRepository` 单例（磁盘读写） |
| `checkProvider` | `Map<fullName, RepoCheckState>`：检测状态（latest / hasUpdate / status / canRetryInstall），手动与后台自动检测共用 |
| `downloadsProvider` | 进行中的下载任务（取消用 CancelToken） |
| `androidEnvProvider` / `platformBridgeProvider` | 平台能力入口 |

> `StateNotifier.state` 是 protected 成员，外部要当前配置时用 `ref.read(configProvider)` 传快照。

## 仓库列表页（`lib/ui/screens/repo_list_screen.dart`）

- **分类分栏**（Android）：`全部 / 普通应用 / LSPosed 模块 / Magisk-KSU 模块` ChoiceChip（含数量）；全选/反选仅作用于当前分类；其它平台全量显示。
- **批量模式**：勾选后出现「检测所选 / 更新所选」。
- **卡片**（`lib/ui/widgets/repo_card.dart`）自上而下：
  1. 标题行：勾选框（批量）+ 头像（APK 图标优先）+ 主/次名称；
  2. 管理按钮行：清空下载 / 更多（更多版本、仓库详情）/ 编辑 / 删除；
  3. 版本信息：已下载 / 已安装 / 仓库最新 + 状态文本；
  4. 操作按钮：检测 / 更新（下载中变暂停）/ 重试安装 / 打开文件夹 / 启动。
- 「启动」按钮可见性：Android = 已知包名**且**应用有启动入口（异步查询缓存 `_launchable`，XP 模块视为可启动）；桌面端 = 配置了 `launchFile`。

## 仓库编辑页（`lib/ui/screens/repo_edit_screen.dart`）

- 粘贴 GitHub 链接自动解析 owner/repo；tag 过滤；自定义名称；检测间隔覆盖；**「有更新时发系统通知」开关**（`notificationsEnabled`）。
- Android 专属：APK 安装授权方式、包名（可反查自动补全）、模块 ID、「下载 APK 后自动获取图标与软件名称」开关。
- **规则编辑**：`RulesLibrary`（按系统分组的预设）+ 多个 `RuleEditor` 卡片；点选规则框后点预设即覆盖。规则框内不再提供策略/架构下拉框（默认 APK + 不限架构，模块/架构由预设写入）。
- 保存时保留自动获取的信息与检测时间，避免编辑丢失。

## 设置页（`lib/ui/screens/settings_screen.dart`）

**草稿机制**：所有修改先存 `SettingsDraft`，点「保存」才提交（详见 02 篇）——保存按钮有未保存圆点，返回时弹确认。

分区：GitHub（Token）→ Android（安装方式、权限与授权、无视签名安装）→ 系统通知 → 下载（线程数、默认文件夹、下载目录）→ 更新检测（全局间隔、后台保活）→ Webhook → 日志（开关、路径、清空）→ 镜像（增删改，prefix/regex）→ 配置导入/导出。

## 更多版本页（`lib/ui/screens/releases_screen.dart`）

列出全部 release（含预发布），分页浏览 + changelog + 下载；下载流程与主界面一致（含 APK 信息提取）。

## 其它组件（`lib/ui/widgets/`）

`repo_avatar`（图标/首字母头像）、`rule_editor` / `rules_library`、`module_terminal`（模块刷入终端窗口，订阅 `ModuleInstallConsole`，更新/重试结束自动关窗）、`android_permission_section`（权限检测/申请 + 无视签名开关）、`path_field`（路径输入 + 文件夹选择）。
