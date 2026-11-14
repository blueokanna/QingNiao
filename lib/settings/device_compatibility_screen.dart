import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../aurora/aurora_widgets.dart';
import '../messaging/message_repository.dart';

class DeviceCompatibilityScreen extends StatefulWidget {
  const DeviceCompatibilityScreen({super.key, required this.repository});
  final MessageRepository repository;

  @override
  State<DeviceCompatibilityScreen> createState() =>
      _DeviceCompatibilityScreenState();
}

class _DeviceCompatibilityScreenState extends State<DeviceCompatibilityScreen>
    with WidgetsBindingObserver {
  Map<dynamic, dynamic>? _device;
  Map<dynamic, dynamic>? _access;
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await Future.wait([
        widget.repository.invoke<Map>('deviceDiagnostics'),
        widget.repository.invoke<Map>('access'),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _device = data[0];
        _access = data[1];
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = tr("Unable to read device status. Try again."));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _open(String method) async {
    try {
      await widget.repository.invoke<void>(method);
    } catch (_) {
      if (mounted) showAuroraSnack(context, tr("This settings page is unavailable. Open App info in system settings."));
    }
  }

  Widget _status(
    String label,
    bool? enabled, {
    String yes = "Enabled",
    String no = "Disabled",
  }) {
    return ListTile(
      title: Text(label),
      subtitle: Text(
        enabled == null
            ? tr("Unavailable")
            : enabled
            ? yes
            : no,
      ),
      leading: Icon(
        enabled == true ? Icons.check_circle_outline : Icons.info_outline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = _device ?? const {};
    final access = _access ?? const {};
    final manufacturer = (device['manufacturer'] as String? ?? '')
        .toLowerCase();
    final guidance = switch (manufacturer) {
      'oneplus' || 'oppo' || 'realme' => tr("ColorOS and OxygenOS may restrict background tasks. If tasks are delayed, check background activity, startup and notification settings. Menu names vary by system version."),
      'xiaomi' || 'redmi' || 'poco' =>
        tr("HyperOS and MIUI may restrict background tasks. If tasks are delayed, check battery, startup and notification settings. Menu names vary by system version."),
      _ => tr("Battery and background restrictions may delay tasks. SMS and MMS also depend on permissions, SIM status and carrier configuration."),
    };
    return AuroraScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const BackButton(),
                 Expanded(child: Text(tr("Device diagnostics"))),
                IconButton(
                  onPressed: _loading ? null : _refresh,
                  tooltip: tr("Refresh"),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (_device != null) ...[
              Text(
                '${device['manufacturer']} ${device['model']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('Android API ${device['sdk']} · com.blue.qingniao'),
              const SizedBox(height: 16),
              _status(tr("Default SMS role"), access['defaultApp'] as bool?),
              _status(tr("Read SMS"), access['readSms'] as bool?),
              _status(tr("Receive SMS"), access['receiveSms'] as bool?),
              _status(tr("Send SMS"), access['sendSms'] as bool?),
              _status(tr("System notifications"), device['notificationsEnabled'] as bool?),
              _status(
                tr("Background restriction"),
                device['batteryRestricted'] as bool?,
                yes: tr("Background activity is restricted"),
                no: tr("No background restriction reported"),
              ),
              _status(tr("Battery saver"), device['powerSaveMode'] as bool?),
              const SizedBox(height: 16),
              Text(guidance),
              const SizedBox(height: 12),
               Text(tr("These are system-reported settings, not evidence of carrier or device compatibility testing.")),
            ],
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: () => _open('appSettings'),
              child:  Text(tr("App permissions and background settings")),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _open('notificationSettings'),
              child:  Text(tr("Notification settings")),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _open('batterySettings'),
              child:  Text(tr("Battery optimization")),
            ),
          ],
        ),
      ),
    );
  }
}
