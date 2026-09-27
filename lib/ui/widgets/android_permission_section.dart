import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';

/// Android 权限与授权区块：存储 / 通知权限、root、Shizuku 的检测与申请，
/// 以及「无视签名强制安装」开关（仅在已获得 root 时显示）。
/// 非 Android 平台整体不显示。
class AndroidPermissionSection extends ConsumerStatefulWidget {
  const AndroidPermissionSection({super.key});

  @override
  ConsumerState<AndroidPermissionSection> createState() =>
      _AndroidPermissionSectionState();
}

class _AndroidPermissionSectionState
    extends ConsumerState<AndroidPermissionSection> {
  bool? _storage;
  bool? _notification;
  bool? _root;
  bool? _shizuku;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  Future<void> refresh() async {
    final env = ref.read(androidEnvProvider);
    if (!env.isAndroid) return;
    setState(() => _busy = true);
    final storage = await env.hasStoragePermission();
    final notif = await env.hasNotificationPermission();
    final root = await env.hasRoot();
    final shizuku = await env.hasShizuku();
    if (!mounted) return;
    setState(() {
      _storage = storage;
      _notification = notif;
      _root = root;
      _shizuku = shizuku;
      _busy = false;
    });
  }

  Future<void> _request(Future<bool> Function() act, String what) async {
    setState(() => _busy = true);
    await act();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已发起「$what」申请；完成后请返回并点「重新检测」')));
  }

  Widget _row({
    required String title,
    required bool? state,
    required String grantedText,
    required String deniedText,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    final ok = state == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                Text(
                  state == null ? '检测中…' : (ok ? grantedText : deniedText),
                  style: TextStyle(
                    fontSize: 12,
                    color: ok
                        ? const Color(0xFF34D399)
                        : const Color(0xFFF87171),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: (_busy || ok) ? null : onPressed,
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(androidEnvProvider);
    if (!env.isAndroid) return const SizedBox.shrink();
    final cfg = ref.watch(configProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Android 权限与授权',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: _busy ? null : refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新检测'),
            ),
          ],
        ),
        _row(
          title: '存储权限（所有文件访问）',
          state: _storage,
          grantedText: '已授权，可使用公共下载目录',
          deniedText: '未授权，默认下载目录不可读写',
          buttonText: '申请',
          onPressed: () => _request(env.requestStoragePermission, '存储权限'),
        ),
        _row(
          title: '通知权限',
          state: _notification,
          grantedText: '已授权，可弹出更新通知',
          deniedText: '未授权，更新通知不会显示',
          buttonText: '申请',
          onPressed: () =>
              _request(env.requestNotificationPermission, '通知权限'),
        ),
        _row(
          title: 'root 权限',
          state: _root,
          grantedText: '已授权，可静默安装/刷模块',
          deniedText: '未授权或未安装 Magisk/KernelSU',
          buttonText: '申请',
          onPressed: () => _request(env.requestRoot, 'root 权限'),
        ),
        _row(
          title: 'Shizuku 授权',
          state: _shizuku,
          grantedText: '可用',
          deniedText: '不可用（未启动或未授权）',
          buttonText: '申请',
          onPressed: () => _request(env.requestShizuku, 'Shizuku 授权'),
        ),
        if (_root == true)
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('无视签名强制安装'),
            subtitle: const Text(
                '签名与应用已装版本不一致时，先卸载原应用再安装（会丢失应用数据，请谨慎开启）。\n'
                '对本应用自身的更新无效：不会卸载自己，会直接拒绝安装。',
                style: TextStyle(fontSize: 12)),
            value: cfg.forceInstallIgnoreSignature,
            onChanged: (v) => ref
                .read(configProvider.notifier)
                .setConfig(cfg.copyWith(forceInstallIgnoreSignature: v)),
          ),
        const Text('授权动作会跳转系统界面，完成后返回本页点「重新检测」刷新状态',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
      ],
    );
  }
}
