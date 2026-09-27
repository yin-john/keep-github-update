import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// 目录路径输入框：手动输入 + 右侧「选择文件夹」按钮。
/// 平台不支持目录选择器（如 Android）时提示手动输入，输入框仍可正常编辑。
class PathField extends StatefulWidget {

  const PathField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.helper,
  });
  final String label;
  final String? hint;
  final String? helper;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<PathField> createState() => _PathFieldState();
}

class _PathFieldState extends State<PathField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(PathField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    String? dir;
    try {
      dir = await getDirectoryPath(
        initialDirectory: _c.text.isEmpty ? null : _c.text,
        confirmButtonText: '选择此文件夹',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('当前平台不支持文件夹选择框，请直接手动输入路径')));
      }
      return;
    }
    final picked = dir;
    if (picked != null && picked.isNotEmpty) {
      setState(() => _c.text = picked);
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        helperMaxLines: 2,
        suffixIcon: IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: '选择文件夹',
          onPressed: _pick,
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}
