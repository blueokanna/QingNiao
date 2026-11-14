import '../messaging/sensitive_clipboard.dart';

import 'package:flutter/material.dart';

import '../aurora/aurora_widgets.dart';
import '../l10n/app_strings.dart';
import '../messaging/message_repository.dart';

class NetworkPushScreen extends StatefulWidget {
  const NetworkPushScreen({super.key, required this.repository});
  final MessageRepository repository;

  @override
  State<NetworkPushScreen> createState() => _NetworkPushScreenState();
}

class _NetworkPushScreenState extends State<NetworkPushScreen> {
  Map _status = const {};
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await widget.repository.invoke<Map>('pushStatus');
      if (mounted) {
        setState(() {
          _status = status ?? {};
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable(bool value) async {
    setState(() => _busy = true);
    try {
      await widget.repository.invoke('pushSetEnabled', {'enabled': value});
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    } finally {
      await _load();
    }
  }

  Future<void> _copyIdentifier() async {
    setState(() => _busy = true);
    try {
      final identifier = await widget.repository.invoke<String>(
        'pushRegistrationId',
      );
      if (identifier == null || identifier.isEmpty) return;
      await SensitiveClipboard.copy(identifier);
      if (mounted) showAuroraSnack(context, tr('Copied'));
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuroraScaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AuroraTopBar(title: tr('Network push')),
          if (_error != null)
            AuroraErrorBanner(message: _error!, onRetry: _load),
          SwitchListTile(
            title: Text(tr('Network push')),
            subtitle: Text(
              _status['configured'] != true
                  ? tr('Firebase is not configured')
                  : _status['services'] != true
                  ? tr('Google Play services are unavailable')
                  : tr('FCM sync alerts'),
            ),
            value: _status['enabled'] == true,
            onChanged:
                _busy ||
                    _status['configured'] != true ||
                    _status['services'] != true
                ? null
                : _enable,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr(
                'Network push alerts you to synced messages. Carrier SMS still uses the mobile network.',
              ),
            ),
          ),
          ListTile(
            title: Text(tr('Copy push identifier')),
            leading: const Icon(Icons.key_rounded),
            enabled: !_busy && _status['enabled'] == true,
            onTap: _copyIdentifier,
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    ),
  );
}
