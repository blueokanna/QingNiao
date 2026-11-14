import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/format.dart';
import '../messaging/message_repository.dart';
import '../messaging/models.dart';
import '../sync/sync_engine.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.repository});

  final MessageRepository repository;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  late final SyncEngine _engine = SyncEngine(widget.repository);
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final status = await _engine.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
        _error = status['error'] == null ? null : '${status['error']}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _syncError(error);
      });
    }
  }

  String _syncError(Object error) =>
      error is SyncException ? error.message : messageError(error);

  bool get _enabled => _status?['enabled'] == true;
  String get _server => '${_status?['serverUrl'] ?? ''}';
  String get _fingerprint {
    final value = '${_status?['fingerprint'] ?? ''}';
    return value.isEmpty ? tr("Not generated") : value;
  }

  String get _pairingCode => '${_status?['pairingCode'] ?? ''}';

  Future<void> _configure({String? url, bool? enabled}) async {
    setState(() => _busy = true);
    try {
      await _engine.configure(
        serverUrl: url ?? _server,
        enabled: enabled ?? _enabled,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _syncError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: _server);
    final url = await showAuroraDialog<String>(
      context: context,
      title:  Text(tr("Sync server")),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration:  InputDecoration(
          hintText: 'https://sync.example.com',
          helperText: tr("Use a self-hosted server for encrypted envelopes"),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child:  Text(tr("Cancel"))),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child:  Text(tr("Save"))),
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
      title:  Text(tr("Enter pairing code")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text(tr("Open Settings > Device sync on the other device and copy its pairing code.")),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration:  InputDecoration(hintText: tr("Pairing code / public key")),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child:  Text(tr("Cancel"))),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child:  Text(tr("Pair"))),
      ],
    );
    if (code == null || code.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await _engine.join(code.trim());
      await _load();
      if (mounted) showAuroraSnack(context, tr("Pairing complete"));
    } catch (error) {
      if (mounted) setState(() => _error = _syncError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      final result = await _engine.syncNow();
      await _load();
      if (mounted) showAuroraSnack(context, result.message);
    } catch (error) {
      if (mounted) setState(() => _error = _syncError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showAuroraDialog<bool>(
      context: context,
      title:  Text(tr("Reset sync keys?")),
      content:  Text(tr("This device identity will be deleted. Other devices will need to pair again.")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child:  Text(tr("Cancel"))),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: context.colors.error),
          child:  Text(tr("Reset")),
        ),
      ],
    );
    if (confirmed != true) return;
    try {
      await _engine.reset();
      await _load();
      if (mounted) showAuroraSnack(context, tr("Sync identity reset"));
    } catch (error) {
      if (mounted) showAuroraSnack(context, _syncError(error));
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
                  title: tr("Device sync"),
                  subtitle: tr("Optional encrypted sync"),
                  actions: [
                    AuroraIconButton(
                      icon: Icons.sync_rounded,
                      tooltip: tr("Sync now"),
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
                                _enabled ? tr("Connected") : tr("Sync is off"),
                                style: context.texts.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _enabled
                                    ? tr("Last synced {p0}", [lastSync == null ? '—' : MessageFormat.duration(DateTime.now().millisecondsSinceEpoch - (lastSync as num).toInt())])
                                    : tr("Sync encrypted messages across your devices"),
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
                                    _enabled ? tr("Receive updates using long polling") : tr("Local first"),
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
                  title: tr("Connection"),
                  children: [
                    AuroraSettingTile(
                      title: tr("Enable sync"),
                      subtitle: _enabled ? tr("Receive encrypted updates in the background") : tr("No sync traffic while disabled"),
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
                      title: tr("Server address"),
                      subtitle: _server.isEmpty ? tr("Not set") : _server,
                      icon: Icons.dns_outlined,
                      onTap: _busy ? null : _editServer,
                      showDivider: true,
                    ),
                    AuroraSettingTile(
                      title: tr("This device's pairing code"),
                      subtitle: _pairingCode.isEmpty ? tr("Generated when sync is enabled") : _pairingCode,
                      icon: Icons.key_rounded,
                      trailing: _pairingCode.isEmpty
                          ? null
                          : IconButton(
                              tooltip: tr("Copy pairing code"),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _pairingCode));
                                if (context.mounted) showAuroraSnack(context, tr("Pairing code copied"));
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                            ),
                      showDivider: true,
                    ),
                    AuroraSettingTile(
                      title: tr("Pair another device"),
                      subtitle: tr("Verify device fingerprints before sharing messages"),
                      icon: Icons.qr_code_2_rounded,
                      onTap: _pair,
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: AuroraSection(
                  title: tr("This device"),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                tr("Device fingerprint"),
                                style: context.texts.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: tr("Copy fingerprint"),
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: _fingerprint));
                                  if (context.mounted) showAuroraSnack(context, tr("Fingerprint copied"));
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
                                  tr("Compare fingerprints through a trusted channel. Identity verification and secure key storage require additional validation."),
                                  style: context.texts.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _reset,
                                style: TextButton.styleFrom(foregroundColor: scheme.error),
                                child:  Text(tr("Reset")),
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
                  title: tr("Paired devices"),
                  children: [
                    if (devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          tr("No other devices yet. Pair a device to exchange encrypted messages."),
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
                    tr("Encryption uses X25519, HKDF and AES-256-GCM.")
                    tr("The server can see routing metadata, timestamps and ciphertext sizes. Envelope encryption alone does not authenticate the sender."),
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
