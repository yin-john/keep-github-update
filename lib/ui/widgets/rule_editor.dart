import 'package:flutter/material.dart';
import '../../core/config/models.dart';

class RuleEditor extends StatefulWidget {

  const RuleEditor({
    super.key,
    required this.platform,
    required this.initial,
    required this.onChanged,
    this.onRemove,
    this.selected = false,
    this.onSelect,
  });

  /// 所属平台（固定为当前宿主系统，不再提供平台下拉框）
  final PlatformType platform;
  final AssetRule initial;
  final ValueChanged<AssetRule> onChanged;
  final VoidCallback? onRemove;

  /// 是否为当前选中规则（规则库点击将覆盖此框）
  final bool selected;
  final VoidCallback? onSelect;

  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  late UpdateStrategy _strategy;
  late TargetArch _arch;
  late bool _verify;
  late ChecksumType _checksumType;
  late final TextEditingController _regex;
  late final TextEditingController _csRegex;
  final List<TextEditingController> _preserveCtrls = []; // 数据目录（可多个）
  final List<TextEditingController> _preserveFileCtrls = []; // 数据文件（可多个）
  late final TextEditingController _installArgs;

  @override
  void initState() {
    super.initState();
    _strategy = widget.initial.strategy;
    if (!widget.platform.supportsStrategy(_strategy)) {
      _strategy = widget.platform.strategies.first;
    }
    _arch = widget.initial.arch;
    _verify = widget.initial.verifyChecksum;
    _checksumType = widget.initial.checksumType;
    _regex = TextEditingController(text: widget.initial.nameRegex);
    _csRegex = TextEditingController(text: widget.initial.checksumRegex ?? '');
    for (final p in widget.initial.preservePaths) {
      _preserveCtrls.add(TextEditingController(text: p));
    }
    for (final p in widget.initial.preserveFiles) {
      _preserveFileCtrls.add(TextEditingController(text: p));
    }
    _installArgs =
        TextEditingController(text: widget.initial.installArgs ?? '');
  }

  @override
  void dispose() {
    _regex.dispose();
    _csRegex.dispose();
    for (final c in _preserveCtrls) {
      c.dispose();
    }
    for (final c in _preserveFileCtrls) {
      c.dispose();
    }
    _installArgs.dispose();
    super.dispose();
  }

  /// 外部覆盖（如点规则库预设）时，同步本地状态与输入框内容
  @override
  void didUpdateWidget(RuleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.initial;
    if (incoming != _currentRule) {
      setState(() {
        _strategy = incoming.platform.supportsStrategy(incoming.strategy)
            ? incoming.strategy
            : incoming.platform.strategies.first;
        _arch = incoming.arch;
        _verify = incoming.verifyChecksum;
        _checksumType = incoming.checksumType;
        _regex.text = incoming.nameRegex;
        _csRegex.text = incoming.checksumRegex ?? '';
        _installArgs.text = incoming.installArgs ?? '';
        final old = List.of(_preserveCtrls);
        _preserveCtrls
          ..clear()
          ..addAll(incoming.preservePaths
              .map((p) => TextEditingController(text: p)));
        final oldFiles = List.of(_preserveFileCtrls);
        _preserveFileCtrls
          ..clear()
          ..addAll(incoming.preserveFiles
              .map((p) => TextEditingController(text: p)));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final c in [...old, ...oldFiles]) {
            c.dispose();
          }
        });
      });
    }
  }

  AssetRule _buildRule() => AssetRule(
        platform: widget.platform,
        strategy: _strategy,
        nameRegex: _regex.text,
        checksumRegex: _csRegex.text.isEmpty ? null : _csRegex.text,
        verifyChecksum: _verify,
        checksumType: _checksumType,
        arch: _arch,
        preservePaths: _preserveCtrls
            .map((c) => c.text.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        preserveFiles: _preserveFileCtrls
            .map((c) => c.text.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        installArgs:
            _installArgs.text.trim().isEmpty ? null : _installArgs.text.trim(),
      );

  /// 当前编辑器所代表的规则
  AssetRule get _currentRule => _buildRule();

  void _emit() => widget.onChanged(_buildRule());

  /// 一组「多条目路径正则」编辑器（数据目录 / 数据文件共用）
  Widget _pathListEditor({
    required String title,
    required List<TextEditingController> ctrls,
    required String hint,
    required String helper,
    required String addLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(title,
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ),
        ...List.generate(
          ctrls.length,
          (i) => Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrls[i],
                  decoration: InputDecoration(
                    hintText: hint,
                    helperText: helper,
                    helperMaxLines: 2,
                    isDense: true,
                  ),
                  onChanged: (_) => _emit(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '删除该条',
                onPressed: () {
                  setState(() => ctrls.removeAt(i).dispose());
                  _emit();
                },
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() => ctrls.add(TextEditingController()));
              _emit();
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(addLabel),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const selectedColor = Color(0xFF3B82F6);
    return Card(
      color: widget.selected ? const Color(0xFF1E3A5F) : const Color(0xFF172033),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.selected ? selectedColor : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onSelect,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              // 头部：选中状态 + 删除
              Row(
                children: [
                  Icon(
                    widget.selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: widget.selected
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.selected ? '已选中（规则库将覆盖此框）' : '点击选中此规则框',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.selected
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                  const Spacer(),
                  if (widget.onRemove != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '删除此规则框',
                      onPressed: widget.onRemove,
                    ),
                ],
              ),
              // 策略与目标架构不再提供下拉框（默认 APK + 不限架构；
              // 需要模块刷入或指定架构时用规则库预设覆盖）
              TextField(
                controller: _regex,
                decoration: const InputDecoration(
                  labelText: '文件名匹配正则',
                  hintText: r'例: .*windows.*\.zip$',
                  helperText: '在 release 产物中匹配目标文件，按 Dart RegExp 语法',
                  helperMaxLines: 2,
                  isDense: true,
                ),
                onChanged: (_) => _emit(),
              ),
              const Divider(height: 16),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('下载后校验完整性'),
                subtitle: const Text('自动查找 release 下的对应校验文件'),
                value: _verify,
                onChanged: (v) => setState(() {
                  _verify = v;
                  _emit();
                }),
              ),
              if (_verify) ...[
                DropdownButton<ChecksumType>(
                  value: _checksumType,
                  isExpanded: true,
                  onChanged: (v) => setState(() {
                    _checksumType = v!;
                    _emit();
                  }),
                  items: ChecksumType.values
                      .map((e) => DropdownMenuItem(
                          value: e, child: Text(e.ext.toUpperCase())))
                      .toList(),
                ),
                TextField(
                  controller: _csRegex,
                  decoration: const InputDecoration(
                    labelText: '校验文件名正则（可选）',
                    isDense: true,
                    hintText: r'例: .*sha256sums.*\.txt$',
                    helperText: '留空则按「产物名.sha256」自动推断校验文件',
                    helperMaxLines: 2,
                  ),
                  onChanged: (_) => _emit(),
                ),
              ],
              if (_strategy == UpdateStrategy.portable) ...[
                _pathListEditor(
                  title: '数据目录排除（覆盖时保留，可指定多个）',
                  ctrls: _preserveCtrls,
                  hint: r'例: ^data/ 或 ^config',
                  helper: '相对安装目录的目录路径正则，匹配到的目录在覆盖时保留',
                  addLabel: '添加数据目录',
                ),
                const SizedBox(height: 6),
                _pathListEditor(
                  title: '数据文件排除（覆盖时保留，可指定多个）',
                  ctrls: _preserveFileCtrls,
                  hint: r'例: ^config\.json$ 或 \.ini$',
                  helper: '相对安装目录的文件路径正则，匹配到的文件在覆盖时保留',
                  addLabel: '添加数据文件',
                ),
              ],
              if (_strategy == UpdateStrategy.installer)
                TextField(
                  controller: _installArgs,
                  decoration: const InputDecoration(
                    labelText: '额外安装参数',
                    hintText: '例: ALLUSERS=1',
                    helperText: 'exe 留空默认 /S；msi 会追加到 msiexec 参数',
                    helperMaxLines: 2,
                    isDense: true,
                  ),
                  onChanged: (_) => _emit(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
