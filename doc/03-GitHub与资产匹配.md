# 03 · GitHub 与资产匹配

[← 返回目录](README.md)

## Release 获取（`lib/core/github/`）

| 文件 | 职责 |
|---|---|
| `api_client.dart` | GitHub REST API 封装（`/repos/{owner}/{repo}/releases/latest` 等），支持 PAT |
| `direct_link_fetcher.dart` | API 不可用时的**直链回退**（解析 releases 页面 / latest 跳转） |
| `release_fetcher.dart` | 统一入口：API 优先 → 直链回退；带缓存；`listReleases` 供「更多版本」页 |

注意事项：

- **Dart `RegExp` 不支持 `(?i)` 内联标志**（构造即抛 FormatException），大小写兼容用字符类 `[Zz]`。
- **Dart 字符串里的 `$` 必须转义 `\$`**（测试里写含 `$` 的 YAML 时踩过坑）。
- 用户在国内，Release 产物下载走镜像改写（见下），API 调用偶发网络 reset 需重试。

## 镜像改写（`MirrorResolver`）

配置 `mirrors` 列表，两种模式：

| 模式 | 行为 |
|---|---|
| `prefix` | 把资产 URL 的指定前缀替换为目标前缀（如 `https://github.com` → `https://mirror.example.com`） |
| `regex` | 按正则整体改写 |

未填写「匹配」的镜像不生效；留空整个列表则直连。

## 资产匹配（`lib/core/matcher/asset_matcher.dart`）

对 release 的每个资产（asset）逐条尝试 `AssetRule`：

```
AssetRule
  platform     所属平台（固定当前宿主系统）
  strategy     更新策略：portable / installer / docker / apk / module
  arch         目标架构（any / arm64 / arm32 / x64 / x86，Android 按 ABI 选）
  nameRegex    文件名匹配正则（Dart RegExp）
  verifyChecksum / checksumType / checksumRegex   可选完整性校验
  preservePaths / preserveFiles                    portable 覆盖时的数据保留正则
  installArgs                                      installer 额外参数
```

匹配结果 `MatchedAsset(rule, asset)` 交给下载与安装层。规则预设见 `lib/core/config/rule_presets.dart`（Android：APK 通用 / APK ARM64 / APK ARM32 / Magisk-KSU 模块）。

## 版本比较（`lib/core/version/installed_version.dart`）

| 函数 | 用途 |
|---|---|
| `normalizeVersion` | 小写、去前导 `v`、去空白 |
| `versionCore` | 提取数字核心（`app-v1.2.3-beta` → `1.2.3`） |
| `compareVersions` | 逐段比较；数字核心相同即视为同版本（`1.2` ≡ `1.2.0`） |
| `versionMatches(installed, tag)` | 已装版本与 tag 是否同版本 |
| `versionMatchesTag(installed, tag)` | **推荐**：兼容 LSPosed 模块仓库的 `<versionCode>-<versionName>` tag（如 `20950-1.3.4` ↔ 应用 versionName `1.3.4`） |

> ⚠️ 所有「已装版本 vs release tag」的比较一律用 `versionMatchesTag`；直接用 `versionMatches` 会让 LSPosed 模块仓库的版本判等永远失败。

## 包名 / 模块 ID 反查（`UpdateService.detectIdentity`）

用于自动补全 `packageName` / `moduleId`（`_learnIdentity`）：

- tag 来源优先级：设备上读到的已装版本 → `lastInstalledTag` → **仓库最新 tag 兜底**（「从外部安装且已是最新版」的场景）。
- APK 仓库：`guessPackageName(versions, installedTag)` 在设备包版本表里找**唯一**版本匹配的包；歧义（多于一个匹配）时放弃并在日志说明原因。
- 模块仓库：遍历已安装模块的 `module.prop`，按 `version` / `versionCode` 匹配。

`_packageVersions()` / `_modules()` 结果按服务实例缓存；`guessPackageName` 的匹配用 `versionMatchesTag`。
