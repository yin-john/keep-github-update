import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/config/models.dart';
import '../../core/github/repo_ref.dart';
import '../../core/platform/platform_utils.dart';
import '../providers/app_providers.dart';
import '../widgets/rule_editor.dart';
import '../widgets/rules_library.dart';

/// 当前宿主系统（用于默认选中对应系统的规则）；异常时回退 Windows
PlatformType _hostPlatform() {
  try {
    return currentPlatformType();
  } catch (_) {
    return PlatformType.windows;
  }
}

/// 规则草稿：用稳定的自增 id 作为 Widget key，避免列表中增删时状态错位
class _RuleDraft {
  _RuleDraft(this.id, this.rule);
  final int id;
  AssetRule rule;
}

class RepoEditScreen extends ConsumerStatefulWidget {
  const RepoEditScreen({super.key, this.repo});
  final RepoConfig? repo;

  @override
  ConsumerState<RepoEditScreen> createState() => _RepoEditScreenState();
}

class _RepoEditScreenState extends ConsumerState<RepoEditScreen> {
  late final TextEditingController _url;
  late final TextEditingController _owner;
  late final TextEditingController _repo;
  late final TextEditingController _tag;
  late final TextEditingController _install;
  late final TextEditingController _container;
  late final TextEditingController _docker;
  late final TextEditingController _packageName;
  late final TextEditingController _moduleId;
  late List<_RuleDraft> _drafts;
  int _nextRuleId = 0;
  int? _selectedRuleId; // 当前选中的规则框（规则库将覆盖它）
  InstallMethod? _apkMethod;
  String? _urlError;
  bool _installEdited = false; // 用户是否手动改过安装目录（改过则不再自动填充）

  @override
  void initState() {
    super.initState();
    final r = widget.repo;
    final host = _hostPlatform();
    _url = TextEditingController();
    _owner = TextEditingController(text: r?.owner ?? '');
    _repo = TextEditingController(text: r?.repo ?? '');
    _tag = TextEditingController(text: r?.tagFilter ?? '');
    _install = TextEditingController(text: r?.installDir ?? '');
    _container = TextEditingController(text: r?.containerName ?? '');
    _docker = TextEditingController(text: r?.dockerRunArgs ?? '');
    _packageName = TextEditingController(text: r?.packageName ?? '');
    _moduleId = TextEditingController(text: r?.moduleId ?? '');
    _apkMethod = r?.apkInstallMethod;
    _installEdited = r != null; // 编辑既有仓库时不自动改写安装目录
    final initialRules = r?.assetRules ??
        [
          // 默认选中「当前所属系统」对应的规则
          AssetRule(
            platform: host,
            strategy: host.strategies.first,
            nameRegex: '.*',
          )
        ];
    _drafts = [for (final x in initialRules) _RuleDraft(_nextRuleId++, x)];
    _selectedRuleId = _drafts.isEmpty ? null : _drafts.first.id;
  }

  /// 解析粘贴的 GitHub 链接 / 简写，填入 owner 与 repo
  void _applyUrl(String input, {bool reportError = false}) {
    final ref = parseGitHubRef(input);
    if (ref != null) {
      setState(() {
        _owner.text = ref.owner;
        _repo.text = ref.repo;
        _urlError = null;
      });
      _autofillInstallDir();
    } else if (reportError) {
      setState(() =>
          _urlError = '无法识别，请粘贴形如 https://github.com/owner/repo 的链接');
    }
  }

  /// 新建仓库时，若配置了「默认文件夹」，安装目录默认填 <默认文件夹>/<作者名>@<repo名>
  void _autofillInstallDir() {
    if (widget.repo != null || _installEdited) return;
    final base = ref.read(configProvider).defaultInstallDir;
    if (base == null || base.isEmpty) return;
    final owner = _owner.text.trim();
    final repo = _repo.text.trim();
    if (owner.isEmpty || repo.isEmpty) return;
    final path = p.join(base, '$owner@$repo');
    if (_install.text != path) setState(() => _install.text = path);
  }

  /// 应用规则库预设：覆盖「当前选中的规则框」；未选中则新增
  void _applyPreset(AssetRule rule) {
    final idx = _drafts.indexWhere((d) => d.id == _selectedRuleId);
    if (idx >= 0) {
      setState(() => _drafts[idx].rule = rule);
    } else {
      _appendRule(rule);
    }
  }

  /// 追加一条新规则框并选中
  void _appendRule(AssetRule rule) {
    final draft = _RuleDraft(_nextRuleId++, rule);
    setState(() {
      _drafts.add(draft);
      _selectedRuleId = draft.id;
    });
  }

  /// 删除规则框：仅移除，不重置为初始规则；若删除的是选中项则选中第一个
  void _removeRule(int index) {
    final removed = _drafts[index];
    setState(() {
      _drafts.removeAt(index);
      if (_selectedRuleId == removed.id) {
        _selectedRuleId = _drafts.isEmpty ? null : _drafts.first.id;
      }
    });
  }

  /// 弹出原生文件夹选择框，选择 Portable/Installer 的安装目录
  Future<void> _pickInstallDir() async {
    final dir = await getDirectoryPath(
      initialDirectory: _install.text.isEmpty ? null : _install.text,
      confirmButtonText: '选择此文件夹',
    );
    if (dir != null && dir.isNotEmpty) {
      setState(() {
        _install.text = dir;
        _installEdited = true;
      });
    }
  }

  void _save() {
    if (_owner.text.isEmpty || _repo.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写 Owner 与 Repo（或粘贴 GitHub 链接）')));
      return;
    }
    if (_drafts.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请至少添加一条匹配规则')));
      return;
    }
    final rules = _drafts.map((d) => d.rule).toList();
    final r = RepoConfig(
      id: widget.repo?.id ?? '${_owner.text}/${_repo.text}',
      owner: _owner.text,
      repo: _repo.text,
      tagFilter: _tag.text.isEmpty ? null : _tag.text,
      assetRules: rules,
      lastInstalledTag: widget.repo?.lastInstalledTag,
      notificationsEnabled: widget.repo?.notificationsEnabled ?? true,
      webhook: widget.repo?.webhook,
      installDir: _install.text.isEmpty ? null : _install.text,
      containerName: _container.text.isEmpty ? null : _container.text,
      dockerRunArgs: _docker.text.isEmpty ? null : _docker.text,
      apkInstallMethod:
          rules.any((x) => x.platform.usesApkInstallMethod) ? _apkMethod : null,
      packageName: rules.any((x) => x.strategy == UpdateStrategy.apk) &&
              _packageName.text.trim().isNotEmpty
          ? _packageName.text.trim()
          : null,
      moduleId: rules.any((x) => x.strategy == UpdateStrategy.module) &&
              _moduleId.text.trim().isNotEmpty
          ? _moduleId.text.trim()
          : null,
    );
    final notifier = ref.read(configProvider.notifier);
    if (widget.repo != null) {
      notifier.updateRepo(r);
    } else {
      notifier.addRepo(r);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // 依据当前规则所用平台/策略，条件化展示对应字段，避免出现其它平台专属选项
    final host = _hostPlatform();
    final rules = _drafts.map((d) => d.rule);
    final strategies = rules.map((x) => x.strategy).toSet();
    final showInstallDir = strategies.any((s) => s.usesInstallDir);
    final showDocker = strategies.any((s) => s.isDocker);
    final showApkMethod = rules.any((x) => x.platform.usesApkInstallMethod);
    // Android 专属：读取设备上真实已装版本所需的标识
    final showPackageName = rules.any((x) => x.strategy == UpdateStrategy.apk);
    final showModuleId = rules.any((x) => x.strategy == UpdateStrategy.module);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.repo != null ? '编辑仓库' : '新增仓库'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // —— 直接粘贴 GitHub 链接 ——
          TextField(
            controller: _url,
            decoration: InputDecoration(
              labelText: 'GitHub 链接（粘贴后自动解析 owner/repo）',
              hintText: 'https://github.com/owner/repo',
              helperText: _urlError == null
                  ? '支持完整链接、git@github.com:owner/repo.git 或 owner/repo 简写'
                  : null,
              helperMaxLines: 2,
              errorText: _urlError,
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(
                icon: const Icon(Icons.download_for_offline_outlined),
                tooltip: '解析链接',
                onPressed: () => _applyUrl(_url.text, reportError: true),
              ),
            ),
            onChanged: (v) => _applyUrl(v),
            onSubmitted: (v) => _applyUrl(v, reportError: true),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _owner,
                  decoration: const InputDecoration(
                    labelText: 'Owner',
                    hintText: '例: microsoft',
                    helperText: '仓库所有者 / 组织',
                  ),
                  onChanged: (_) => _autofillInstallDir(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _repo,
                  decoration: const InputDecoration(
                    labelText: 'Repo',
                    hintText: '例: vscode',
                    helperText: '仓库名',
                  ),
                  onChanged: (_) => _autofillInstallDir(),
                ),
              ),
            ],
          ),
          TextField(
            controller: _tag,
            decoration: const InputDecoration(
              labelText: 'Tag 过滤（可选）',
              hintText: '例: stable 或 v1.',
              helperText: '仅匹配包含该字符串的 tag；留空表示不过滤',
            ),
          ),
          if (showInstallDir)
            TextField(
                controller: _install,
                decoration: InputDecoration(
                    labelText: 'Portable 安装目录',
                    hintText: r'例: D:\Apps\MyTool',
                    helperText: 'portable 解压覆盖的目标目录；可点右侧选择文件夹',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.folder_open),
                      tooltip: '选择文件夹',
                      onPressed: _pickInstallDir,
                    )),
                onChanged: (_) => _installEdited = true),
          if (showDocker) ...[
            TextField(
                controller: _container,
                decoration: const InputDecoration(
                  labelText: 'Docker 容器名',
                  hintText: '例: my-app',
                  helperText: 'docker 更新时重建的容器名',
                )),
            TextField(
                controller: _docker,
                decoration: const InputDecoration(
                  labelText: 'Docker run 额外参数（可选）',
                  hintText: '例: --rm -v /data:/data -p 8080:8080',
                  helperText: '重建容器时附加到 docker run 的参数',
                )),
          ],
          if (showApkMethod)
            DropdownButton<InstallMethod?>(
              value: _apkMethod,
              isExpanded: true,
              hint: const Text('Android APK 安装授权方式'),
              onChanged: (v) => setState(() => _apkMethod = v),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(
                      '跟随全局默认 (${ref.watch(configProvider).defaultApkInstallMethod.label})'),
                ),
                ...InstallMethod.values.map((e) => DropdownMenuItem(
                    value: e, child: Text(e.label))),
              ],
            ),
          if (showPackageName)
            TextField(
              controller: _packageName,
              decoration: const InputDecoration(
                labelText: '已装应用包名（Android APK）',
                hintText: '例: com.example.app',
                helperText: '用于读取设备上该应用的已装版本；留空时会尝试自动识别',
                helperMaxLines: 2,
              ),
            ),
          if (showModuleId)
            TextField(
              controller: _moduleId,
              decoration: const InputDecoration(
                labelText: '模块 ID（Magisk / KernelSU）',
                hintText: '例: my_module_id',
                helperText: '用于读取设备上模块 module.prop 的版本；留空则按 updateJson/名称自动匹配',
                helperMaxLines: 2,
              ),
            ),
          const SizedBox(height: 12),
          // —— 规则库：按系统分组 ——
          RulesLibrary(onPick: _applyPreset),
          const SizedBox(height: 4),
          const Text('资产匹配规则',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const Text('点击某个规则框选中后，再点规则库预设即可覆盖该框',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          const SizedBox(height: 4),
          if (_drafts.isEmpty)
            const Card(
              color: Color(0xFF172033),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: Color(0xFF94A3B8)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('尚无规则，请从上方「规则库」选择，或点下方按钮添加',
                          style: TextStyle(color: Color(0xFF94A3B8))),
                    ),
                  ],
                ),
              ),
            ),
          ..._drafts.asMap().entries.map((e) => RuleEditor(
                key: ValueKey(e.value.id),
                initial: e.value.rule,
                selected: e.value.id == _selectedRuleId,
                onSelect: () => setState(() => _selectedRuleId = e.value.id),
                onChanged: (nr) => setState(() => e.value.rule = nr),
                onRemove: () => _removeRule(e.key),
              )),
          TextButton.icon(
            onPressed: () => _appendRule(AssetRule(
                platform: host,
                strategy: host.strategies.first,
                nameRegex: '')),
            icon: const Icon(Icons.add),
            label: Text('添加 ${host.name} 规则'),
          ),
        ],
      ),
    );
  }
}
