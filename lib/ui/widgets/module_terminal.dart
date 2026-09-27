/// 模块安装「终端窗口」：实时显示刷入输出。
///
/// 部分模块安装脚本需要交互（如音量键选择）：脚本以 root 运行时，
/// 会通过 getevent 直接读取按键事件，本窗口如实展示脚本的提示与输出。
/// 窗口在安装流程结束后由调用方（更新/重试安装）自动关闭，也可手动关闭。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/module_console.dart';

/// 终端窗口句柄：调用方在安装结束后调用 [close] 自动关窗
class ModuleTerminalHandle {
  ModuleTerminalHandle(this._close);
  final Future<void> Function() _close;

  Future<void> close() => _close();
}

/// 打开模块安装终端窗口
ModuleTerminalHandle openModuleTerminal(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  var closed = false;

  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (navigator.canPop()) navigator.pop();
  }

  unawaited(showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF101827),
        title: const Text('模块安装终端',
            style: TextStyle(fontSize: 16, color: Colors.white)),
        content: const SizedBox(
            width: double.maxFinite, height: 320, child: _TerminalView()),
        actions: [
          TextButton(onPressed: close, child: const Text('关闭窗口')),
        ],
      ),
    ),
  ));
  return ModuleTerminalHandle(close);
}

class _TerminalView extends StatefulWidget {
  const _TerminalView();

  @override
  State<_TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<_TerminalView> {
  final _lines = <String>[];
  final _scroll = ScrollController();
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ModuleInstallConsole.stream.listen((line) {
      if (!mounted) return;
      setState(() {
        _lines.add(line);
        if (_lines.length > 1000) {
          _lines.removeRange(0, _lines.length - 1000);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(6),
      ),
      child: _lines.isEmpty
          ? const Text('等待安装器输出…',
              style: TextStyle(
                  color: Colors.white38,
                  fontFamily: 'monospace',
                  fontSize: 12))
          : ListView.builder(
              controller: _scroll,
              itemCount: _lines.length,
              itemBuilder: (_, i) => Text(
                _lines[i],
                style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 12),
              ),
            ),
    );
  }
}
