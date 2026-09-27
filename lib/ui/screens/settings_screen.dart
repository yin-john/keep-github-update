import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_paths.dart';
import '../../core/config/config_repository.dart';
import '../../core/config/models.dart';
import '../../core/log/app_log.dart';
import '../providers/app_providers.dart';
import '../widgets/android_permission_section.dart';
import '../widgets/path_field.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _token;
  late final TextEditingController _whUrl;
  late final TextEditingController _importPath;
  final List<int> _mirrorIds = [];
  int _nextMirrorId = 0;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    _token = TextEditingController(text: cfg.githubToken ?? '');
    _whUrl = TextEditingController(text: cfg.webhook.url);
    _importPath = TextEditingController();
    _mirrorIds.addAll(List.generate(cfg.mirrors.length, (_) => _nextMirrorId++));
  }

  @override
  void dispose() {
    _token.dispose();
    _whUrl.dispose();
    _importPath.dispose();
    super.dispose();
  }

  /// 以「最新 provider 配置」为基础做增量修改，避免用过期的本地副本覆盖仓库列表等字段
  void _patch(AppConfig Function(AppConfig base) patch, {bool notify = false}) {
    final base = ref.read(configProvider);
    ref.read(configProvider.notifier).setConfig(patch(base));
    if (notify) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置已保存')));
    }
  }

  void _save() {
    _patch(
      (b) => b.copyWith(
        githubToken: _token.text.isEmpty ? null : _token.text,
        webhook: b.webhook.copyWith(url: _whUrl.text),
      ),
      notify: true,
    );
    AppLog.info('保存设置（Token / Webhook）');
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  /// 选择配置文件（导入用）；平台不支持文件选择时提示手动输入
  Future<void> _pickConfigFile() async {
    try {
      final f = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: '配置文件', extensions: ['yaml', 'yml', 'json']),
      ]);
      if (f == null) return;
      setState(() => _importPath.text = f.path);
    } catch (_) {
      _snack('当前平台不支持文件选择框，请手动输入路径');
    }
  }

  /// 导入配置：空路径 / 空文件 / 不含仓库都会被拦下，不会清空现有配置
  Future<void> _doImport() async {
    final path = _importPath.text.trim();
    if (path.isEmpty) {
      _snack('请先填写或选择要导入的配置文件');
      return;
    }
    final repo = ref.read(configRepoProvider);
    try {
      await repo.import(path);
    } on ConfigException catch (e) {
      if (!e.message.contains('不含任何仓库')) {
        _snack('导入失败：$e');
        return;
      }
      // 确属空配置时，二次确认后才允许覆盖
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('该配置不含任何仓库'),
          content: const Text('继续导入会用空配置覆盖当前的仓库列表，确定要继续吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('仍然导入')),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await repo.import(path, allowEmpty: true);
      } catch (e2) {
        _snack('导入失败：$e2');
        return;
      }
    } catch (e) {
      _snack('导入失败：$e');
      return;
    }
    await ref.read(configProvider.notifier).reload();
    final cfg = ref.read(configProvider);
    setState(() {
      _token.text = cfg.githubToken ?? '';
      _whUrl.text = cfg.webhook.url;
      _mirrorIds
        ..clear()
        ..addAll(List.generate(cfg.mirrors.length, (_) => _nextMirrorId++));
    });
    _snack('已导入配置（仓库 ${cfg.repos.length} 个）');
  }

  /// 导出配置：路径为空时弹「另存为」；失败时给出提示
  Future<void> _doExport() async {
    var path = _importPath.text.trim();
    if (path.isEmpty) {
      try {
        final loc = await getSaveLocation(suggestedName: 'grku_config.yaml');
        if (loc == null) return;
        path = loc.path;
      } catch (_) {
        _snack('请先填写导出文件路径');
        return;
      }
    }
    try {
      final written = await ref.read(configRepoProvider).export(path);
      setState(() => _importPath.text = written);
      _snack('已导出到 $written');
    } catch (e) {
      _snack('导出失败：$e');
    }
  }

  void _updateMirror(int i, MirrorConfig m) {
    _patch((b) {
      if (i >= b.mirrors.length) return b;
      final ms = [...b.mirrors];
      ms[i] = m;
      return b.copyWith(mirrors: ms);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider);
    // 保证镜像 key 列表与镜像数量一致：
    // 配置是异步加载的，initState 时可能还是空配置，加载后镜像数量会变化，
    // 若不同步会导致 _mirrorIds[i] 越界（release 下表现为整页灰色）。
    while (_mirrorIds.length < cfg.mirrors.length) {
      _mirrorIds.add(_nextMirrorId++);
    }
    while (_mirrorIds.length > cfg.mirrors.length) {
      _mirrorIds.removeLast();
    }
    // 仅当存在 Android 规则时，才展示 Android 专属（root/shizuku）设置
    final hasAndroidRepo = cfg.repos
        .any((r) => r.assetRules.any((x) => x.platform.usesApkInstallMethod));
    return Scaffold(
      appBar: AppBar(
          title: const Text('设置'),
          actions: [TextButton(onPressed: _save, child: const Text('保存'))]),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('GitHub', style: TextStyle(fontWeight: FontWeight.w600)),
          TextField(
            controller: _token,
            decoration: const InputDecoration(
              labelText: 'Personal Access Token（可选）',
              hintText: 'ghp_xxxxxxxxxxxxxxxx',
              helperText: '提高 API 速率限制、可访问私有仓库；留空则匿名访问',
              helperMaxLines: 2,
            ),
            obscureText: true,
          ),
          if (hasAndroidRepo) ...[
            const SizedBox(height: 12),
            const Text('Android',
                style: TextStyle(fontWeight: FontWeight.w600)),
            DropdownButton<InstallMethod>(
              value: cfg.defaultApkInstallMethod,
              isExpanded: true,
              hint: const Text('APK 静默安装默认授权方式'),
              onChanged: (v) =>
                  _patch((b) => b.copyWith(defaultApkInstallMethod: v!)),
              items: InstallMethod.values
                  .map((e) =>
                      DropdownMenuItem(value: e, child: Text(e.label)))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          const AndroidPermissionSection(),
          const Divider(),
          SwitchListTile(
            title: const Text('系统级通知'),
            value: cfg.systemNotificationsEnabled,
            onChanged: (v) =>
                _patch((b) => b.copyWith(systemNotificationsEnabled: v)),
          ),
          const Divider(),
          const Text('下载', style: TextStyle(fontWeight: FontWeight.w600)),
          Row(
            children: [
              const Text('下载线程数'),
              Expanded(
                child: Slider(
                  value: cfg.downloadThreads.clamp(1, 16).toDouble(),
                  min: 1,
                  max: 16,
                  divisions: 15,
                  label: '${cfg.downloadThreads}',
                  onChanged: (v) =>
                      _patch((b) => b.copyWith(downloadThreads: v.round())),
                ),
              ),
              SizedBox(
                width: 24,
                child: Text('${cfg.downloadThreads}',
                    textAlign: TextAlign.end),
              ),
            ],
          ),
          const Text('1 = 单线程（支持断点续传）；大于 1 时分块并发下载，服务器不支持时自动回退',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          const SizedBox(height: 8),
          PathField(
            label: '默认文件夹（可选）',
            value: cfg.defaultInstallDir ?? '',
            hint: r'例: D:\Apps 或 /storage/emulated/0/grku',
            helper: '新建仓库时安装目录默认填 <默认文件夹>/<作者名>@<repo名>；可直接输入或点右侧选择文件夹',
            onChanged: (v) => _patch(
                (b) => b.copyWith(defaultInstallDir: v.isEmpty ? null : v)),
          ),
          const SizedBox(height: 8),
          PathField(
            label: '下载目录',
            value: cfg.downloadDir ?? '',
            hint: '留空使用默认：${defaultDownloadDir()}',
            helper: '下载产物存放位置；Android 的公共目录需要存储权限，未授权时可改填应用私有目录',
            onChanged: (v) =>
                _patch((b) => b.copyWith(downloadDir: v.isEmpty ? null : v)),
          ),
          const Divider(),
          const Text('Webhook', style: TextStyle(fontWeight: FontWeight.w600)),
          SwitchListTile(
            title: const Text('启用 Webhook'),
            value: cfg.webhook.enabled,
            onChanged: (v) =>
                _patch((b) => b.copyWith(webhook: b.webhook.copyWith(enabled: v))),
          ),
          if (cfg.webhook.enabled) ...[
            TextField(
              controller: _whUrl,
              decoration: const InputDecoration(
                labelText: 'Webhook URL',
                hintText: '例: https://open.feishu.cn/open-apis/bot/v2/hook/xxxx',
                helperText: '发生所选事件时向该地址 POST JSON',
                helperMaxLines: 2,
              ),
              onChanged: (v) => _patch(
                  (b) => b.copyWith(webhook: b.webhook.copyWith(url: v))),
            ),
            const SizedBox(height: 6),
            const Text('触发事件'),
            ...NotificationEvent.values.map((e) => CheckboxListTile(
                  dense: true,
                  title: Text(e.name),
                  value: cfg.webhook.events.contains(e),
                  onChanged: (v) => _patch((b) {
                    final set = {...b.webhook.events};
                    if (v == true) {
                      set.add(e);
                    } else {
                      set.remove(e);
                    }
                    return b.copyWith(
                        webhook: b.webhook.copyWith(events: set.toList()));
                  }),
                )),
          ],
          const Divider(),
          const Text('日志', style: TextStyle(fontWeight: FontWeight.w600)),
          SwitchListTile(
            title: const Text('记录操作日志'),
            subtitle: const Text('检测 / 更新 / 配置变更等操作写入日志文件'),
            value: cfg.loggingEnabled,
            onChanged: (v) {
              AppLog.configure(v);
              if (v) AppLog.info('开启日志');
              _patch((b) => b.copyWith(loggingEnabled: v));
            },
          ),
          if (cfg.loggingEnabled) ...[
            Row(
              children: [
                const Expanded(
                  child: Text('日志文件路径',
                      style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                TextButton(
                  onPressed: () {
                    AppLog.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已清空日志')));
                  },
                  child: const Text('清空'),
                ),
              ],
            ),
            SelectableText(AppLog.logFilePath,
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF93C5FD))),
          ],
          const Divider(),
          const Text('镜像', style: TextStyle(fontWeight: FontWeight.w600)),
          const Text('未填写「匹配」的镜像不会生效；如需直连请留空整个列表',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          const SizedBox(height: 6),
          ...cfg.mirrors.asMap().entries.map((entry) {
            final i = entry.key;
            return _MirrorCard(
              key: ValueKey(_mirrorIds[i]),
              initial: entry.value,
              onChanged: (nm) => _updateMirror(i, nm),
              onDelete: () {
                setState(() => _mirrorIds.removeAt(i));
                _patch((b) => b.copyWith(mirrors: [...b.mirrors]..removeAt(i)));
                AppLog.info('删除镜像 #$i');
              },
            );
          }),
          TextButton.icon(
            onPressed: () {
              setState(() => _mirrorIds.add(_nextMirrorId++));
              _patch((b) => b.copyWith(mirrors: [
                    ...b.mirrors,
                    const MirrorConfig(
                        name: '新镜像',
                        mode: MirrorMode.prefix,
                        pattern: '',
                        replacement: '')
                  ]));
              AppLog.info('添加镜像');
            },
            icon: const Icon(Icons.add),
            label: const Text('添加镜像'),
          ),
          const Divider(),
          const Text('配置导入/导出',
              style: TextStyle(fontWeight: FontWeight.w600)),
          TextField(
            controller: _importPath,
            decoration: InputDecoration(
              labelText: '配置文件路径（导入 / 导出）',
              hintText: r'例: D:\config\grku_config.yaml',
              helperText: '可手动输入，或点右侧选择文件；导出时留空会弹出「另存为」',
              helperMaxLines: 2,
              suffixIcon: IconButton(
                icon: const Icon(Icons.file_open_outlined),
                tooltip: '选择配置文件',
                onPressed: _pickConfigFile,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _importPath.text.trim().isEmpty ? null : _doImport,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('导入'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _doExport,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('导出'),
              ),
            ],
          ),
          const Text('导入会先校验：路径为空、文件为空或不含任何仓库时都会被拦下，不会清空现有配置',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}

/// 单个镜像编辑卡片：自身持有 TextEditingController，
/// 避免父级每次重建时重新创建控制器导致输入文字错乱。
class _MirrorCard extends StatefulWidget {

  const _MirrorCard({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onDelete,
  });
  final MirrorConfig initial;
  final ValueChanged<MirrorConfig> onChanged;
  final VoidCallback onDelete;

  @override
  State<_MirrorCard> createState() => _MirrorCardState();
}

class _MirrorCardState extends State<_MirrorCard> {
  late final TextEditingController _name;
  late final TextEditingController _pattern;
  late final TextEditingController _replacement;
  late MirrorMode _mode;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial.name);
    _pattern = TextEditingController(text: widget.initial.pattern);
    _replacement = TextEditingController(text: widget.initial.replacement);
    _mode = widget.initial.mode;
  }

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    _replacement.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(MirrorConfig(
        name: _name.text,
        mode: _mode,
        pattern: _pattern.text,
        replacement: _replacement.text,
      ));

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF172033),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '例: gh-proxy',
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  tooltip: '删除镜像',
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            DropdownButton<MirrorMode>(
              value: _mode,
              isExpanded: true,
              onChanged: (v) {
                setState(() => _mode = v!);
                _emit();
              },
              items: MirrorMode.values
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                  .toList(),
            ),
            TextField(
              controller: _pattern,
              decoration: InputDecoration(
                labelText: '匹配（前缀或正则）',
                hintText: '例: https://github.com',
                helperText: _pattern.text.isEmpty
                    ? '未填写，该镜像不会生效'
                    : 'prefix 模式填待替换前缀；regex 模式填正则表达式',
                helperMaxLines: 2,
              ),
              onChanged: (_) {
                setState(() {}); // 刷新 helper 文本
                _emit();
              },
            ),
            TextField(
              controller: _replacement,
              decoration: const InputDecoration(
                labelText: '替换为',
                hintText: '例: https://mirror.example.com',
              ),
              onChanged: (_) => _emit(),
            ),
          ],
        ),
      ),
    );
  }
}
