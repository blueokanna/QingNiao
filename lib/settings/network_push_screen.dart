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
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in ['projectId', 'applicationId', 'senderId', 'apiKey'])
      key: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _load(fillFields: true);
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _fillFields(Map values) {
    for (final entry in _fields.entries) {
      entry.value.text = values[entry.key] as String? ?? '';
    }
  }

  Future<void> _load({bool fillFields = false}) async {
    try {
      final status = await widget.repository.invoke<Map>('pushStatus');
      if (mounted) {
        setState(() {
          _status = status ?? {};
          if (fillFields) _fillFields(_status['configuration'] as Map? ?? {});
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final values = await widget.repository.invoke<Map>(
        'pickFirebaseConfiguration',
      );
      if (!mounted || values == null) return;
      setState(() {
        _fillFields(values);
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            'Choose google-services.json for com.blue.qingniao. Service account keys are not accepted.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({bool reset = false}) async {
    if (!reset && !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.invoke(
        reset ? 'pushResetConfiguration' : 'pushSaveConfiguration',
        reset
            ? null
            : {
                for (final entry in _fields.entries)
                  entry.key: entry.value.text.trim(),
              },
      );
      await _load(fillFields: true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            'Check the Firebase project fields and disable push before changing projects.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _configurationField(String key, String label, String hint) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_busy && _status['enabled'] != true,
      autocorrect: false,
      enableSuggestions: false,
      obscureText: key == 'apiKey',
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 3,
      ),
      validator: (raw) {
        final value = raw?.trim() ?? '';
        final valid = switch (key) {
          'projectId' => RegExp(
            r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$',
          ).hasMatch(value),
          'senderId' => RegExp(r'^[0-9]{6,20}$').hasMatch(value),
          'applicationId' =>
            RegExp(r'^1:[0-9]{6,20}:android:[a-fA-F0-9]{8,64}$')
                    .hasMatch(value) &&
                value.split(':')[1] == _fields['senderId']!.text.trim(),
          'apiKey' => RegExp(r'^AIza[A-Za-z0-9_-]{35}$').hasMatch(value),
          _ => false,
        };
        return valid ? null : tr('Check this Firebase field');
      },
    ),
  );

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
          AuroraSection(
            title: tr('Connection'),
            children: [
              SwitchListTile(
                title: Text(tr('Network push')),
                subtitle: Text(
                  _status['restartRequired'] == true
                      ? tr(
                          'Project saved. Close the app completely and reopen it to apply the change.',
                        )
                      : _status['configured'] != true
                      ? tr('Firebase is not configured')
                      : _status['services'] != true
                      ? tr('Google Play services are unavailable')
                      : tr('FCM sync alerts'),
                ),
                value: _status['enabled'] == true,
                onChanged:
                    _busy ||
                        (_status['enabled'] != true &&
                            (_status['configured'] != true ||
                                _status['services'] != true))
                    ? null
                    : _enable,
              ),
              if (_status['projectId'] is String)
                ListTile(
                  title: Text(tr('Firebase project')),
                  subtitle: Text(_status['projectId'] as String),
                ),
              if (_status['restartRequired'] == true)
                TextButton(
                  onPressed: () => widget.repository.openAppSettings(),
                  child: Text(tr('App settings')),
                ),
            ],
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
          AuroraSection(
            title: tr('Firebase project'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy || _status['enabled'] == true
                            ? null
                            : _import,
                        icon: const Icon(Icons.file_open_outlined),
                        label: Text(tr('Import google-services.json')),
                      ),
                      const SizedBox(height: 16),
                      _configurationField(
                        'projectId',
                        tr('Project ID'),
                        'project_info.project_id',
                      ),
                      _configurationField(
                        'senderId',
                        tr('Project number'),
                        'project_info.project_number',
                      ),
                      _configurationField(
                        'applicationId',
                        tr('Android application ID'),
                        'client_info.mobilesdk_app_id',
                      ),
                      _configurationField(
                        'apiKey',
                        tr('Firebase API key'),
                        'api_key.current_key',
                      ),
                      FilledButton.icon(
                        onPressed: _busy || _status['enabled'] == true
                            ? null
                            : () => _save(),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(tr('Save configuration')),
                      ),
                      if (_status['custom'] == true)
                        TextButton(
                          onPressed: _busy || _status['enabled'] == true
                              ? null
                              : () => _save(reset: true),
                          child: Text(tr('Use bundled configuration')),
                        ),
                      if (_status['enabled'] == true)
                        Text(
                          tr(
                            'Disable network push before changing its project.',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          AuroraSection(
            title: tr('Get Firebase configuration'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        'Create or open your Firebase project, add an Android app with package com.blue.qingniao, then download google-services.json. Import it above and enable network push.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr(
                        'Saving validates the configuration format. Registration still requires your real project and Google Play services.',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await widget.repository.invoke('openFirebaseConsole');
                        } catch (error) {
                          if (context.mounted) {
                            showAuroraSnack(context, messageError(error));
                          }
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: Text(tr('Open Firebase console')),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    ),
  );
}
