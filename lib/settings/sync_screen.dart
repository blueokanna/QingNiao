import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/format.dart';
import '../messaging/message_repository.dart';
import '../messaging/models.dart';

/// 青鸟同步：设备身份、指纹、配对与手动同步。
/// 正文以 X25519 + AES-256-GCM 信封加密，服务器只保存密文。
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.repository});

  final MessageRepository repository;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await widget.repository.syncStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = messageError(error);
      });
    }
  }

  bool get _enabled => _status?['enabled'] == true;
  String get _server => '${_status?['serverUrl'] ?? ''}';
  String get _fingerprint => '${_status?['fingerprint'] ?? '尚未生成'}';

  Future<void> _configure({String? url, bool? enabled}) async {
    setState(() => _busy = true);
    try {
      final status = await widget.repository.syncConfigure(
        serverUrl: url ?? _server,
        enabled: enabled ?? _enabled,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: _server);
    final url = await showAuroraDialog<String>(
      context: context,
      title: const Text('同步服务器'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          hintText: 'https://sync.example.com',
          helperText: '自建服务器；只保存加密信封',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
      ],
    );
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await _configure(url: trimmed, enabled: true);
  }

  Future<void> _pair() async {
    final controller = TextEditingController();
    final code = await showAuroraDialog<String>(
      context: context,
      title: const Text('输入配对码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('在另一台设备上打开「设置 → 青鸟同步」，复制它的配对码。'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '配对码 / 公钥'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('配对')),
      ],
    );
    if (code == null || code.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final status = await widget.repository.syncPair(code.trim());
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
      showAuroraSnack(context, '配对成功，接下来只传输加密信封');
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      final status = await widget.repository.syncNow();
      if (!mounted) return;
      setState(() => _status = status);
      showAuroraSnack(context, '已同步 · 待发送 ${status['pending'] ?? 0} 条');
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showAuroraDialog<bool>(
      context: context,
      title: const Text('重置同步密钥？'),
      content: const Text('本机的设备密钥会被删除，已配对设备需要重新配对。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: context.colors.error),
          child: const Text('重置'),
        ),
      ],
    );
    if (confirmed != true) return;
    try {
      await widget.repository.syncReset();
      await _load();
      if (mounted) showAuroraSnack(context, '已重置同步身份');
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final aurora = context.aurora;
    final devices = (_status?['devices'] as List? ?? const [])
        .whereType<Map>()
        .map(SyncDevice.fromMap)
        .toList(growable: false);
    final lastSync = _status?['lastSync'];
    return AuroraScaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: scheme.primary,
          backgroundColor: scheme.surfaceContainerHigh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: AuroraTopBar(
                  title: '青鸟同步',
                  subtitle: '端到端加密 · 可选',
                  actions: [
                    AuroraIconButton(
                      icon: Icons.sync_rounded,
                      tooltip: '立即同步',
                      onPressed: _busy || !_enabled ? null : _syncNow,
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: AuroraGlass(
                    radius: 30,
                    padding: const EdgeInsets.all(20),
                    gradient: [
                      Color.alphaBlend(aurora.auroraA.withValues(alpha: .16), scheme.surface),
                      Color.alphaBlend(aurora.auroraB.withValues(alpha: .1), scheme.surface),
                    ],
                    child: Row(
                      children: [
                        AuroraBloom(size: 76, static: !_enabled),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _enabled ? '已连接' : '未开启同步',
                                style: context.texts.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _enabled
                                    ? '最近同步 ${lastSync == null ? '—' : MessageFormat.duration(DateTime.now().millisecondsSinceEpoch - (lastSync as num).toInt())}'
                                    : '开启后，短信在多台设备间以密文流转',
                                style: context.texts.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _enabled
                                          ? aurora.success
                                          : scheme.outline.withValues(alpha: .5),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _enabled ? '长轮询实时接收' : '本地优先',
                                    style: context.texts.labelSmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null)
                SliverToBoxAdapter(child: AuroraErrorBanner(message: _error!, onRetry: _load)),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: AuroraLoading()),
                  ),
                ),
              SliverToBoxAdapter(
                child: AuroraSection(
                  title: '连接',
                  children: [
                    AuroraSettingTile(
                      title: '启用同步',
                      subtitle: _enabled ? '在后台保持加密长轮询' : '关闭时完全离线',
                      icon: Icons.cloud_sync_outlined,
                      trailing: Switch(
                        value: _enabled,
                        onChanged: _busy
                            ? null
                            : (value) => _configure(enabled: value),
                      ),
                      showDivider: true,
                    ),
                    AuroraSettingTile(
                      title: '服务器地址',
                      subtitle: _server.isEmpty ? '未设置' : _server,
                      icon: Icons.dns_outlined,
                      onTap: _busy ? null : _editServer,
                      showDivider: true,
                    ),
                    AuroraSettingTile(
                      title: '配对另一台设备',
                      subtitle: '交换公钥指纹后才会解密',
                      icon: Icons.qr_code_2_rounded,
                      onTap: _pair,
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: AuroraSection(
                  title: '本机身份',
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '设备指纹',
                                style: context.texts.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: '复制指纹',
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: _fingerprint));
                                  if (context.mounted) showAuroraSnack(context, '指纹已复制');
                                },
                                icon: const Icon(Icons.copy_rounded, size: 18),
                              ),
                            ],
                          ),
                          Text(
                            _fingerprint,
                            style: context.texts.titleSmall?.copyWith(
                              fontFamily: 'monospace',
                              letterSpacing: 1.2,
                              color: aurora.otp,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '指纹用于核对设备身份。服务器永远拿不到明文与私钥。',
                                  style: context.texts.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _reset,
                                style: TextButton.styleFrom(foregroundColor: scheme.error),
                                child: const Text('重置'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: AuroraSection(
                  title: '已配对设备',
                  children: [
                    if (devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          '还没有其他设备。配对后，短信会在设备之间以密文同步。',
                          style: context.texts.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (final device in devices)
                      AuroraSettingTile(
                        title: device.name,
                        subtitle: '${device.fingerprint} · ${device.thisDevice ? '本机' : '已配对'}',
                        icon: device.thisDevice ? Icons.phone_android_rounded : Icons.devices_rounded,
                        trailing: device.thisDevice
                            ? Icon(Icons.check_circle_rounded, color: scheme.primary, size: 18)
                            : null,
                        showDivider: device != devices.last,
                      ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 40),
                  child: Text(
                    '安全模型：每台设备生成 X25519 密钥对；内容密钥经 HKDF 派生后用 AES-256-GCM 加密；'
                    '信封只携带临时公钥、nonce 与密文。服务器可见账号、时间与密文大小。',
                    style: context.texts.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.7,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
