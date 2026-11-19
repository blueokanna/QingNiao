import 'package:qingniao/l10n/app_strings.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../design/message_theme.dart';
import 'message_repository.dart';

class MmsScreen extends StatefulWidget {
  const MmsScreen({super.key, required this.repository});
  final MessageRepository repository;
  @override
  State<MmsScreen> createState() => _MmsScreenState();
}

class _MmsScreenState extends State<MmsScreen> {
  List<MessageRecord> _messages = [];
  StreamSubscription<String>? _changes;
  String? _error;
  bool _busy = false, _more = false;
  bool _openingAttachment = false;
  @override
  void initState() {
    super.initState();
    _load();
    _changes = widget.repository.changes.listen(
      (_) => _load(),
      onError: (Object error) {
        if (mounted) setState(() => _error = messageError(error));
      },
    );
  }

  Future<void> _load({bool older = false}) async {
    try {
      final rows = await widget.repository.records('mmsMessages', {
        if (older && _messages.isNotEmpty) 'before': _messages.last['id'],
      });
      if (mounted) {
        setState(() {
          _messages = older ? [..._messages, ...rows] : rows;
          _more = rows.length == 50;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    }
  }

  Future<void> _preview(Map attachment) async {
    if (_openingAttachment) return;
    _openingAttachment = true;
    ResizeImage? preview;
    try {
      final bytes = await widget.repository.invoke<Uint8List>('mmsImage', {
        'id': int.parse(attachment['id'] as String),
      });
      if (!mounted ||
          bytes == null ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final image = ResizeImage(
        MemoryImage(bytes),
        width: 1440,
        height: 1440,
        policy: ResizeImagePolicy.fit,
      );
      preview = image;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  child: Image(
                    image: image,
                    errorBuilder: (_, _, _) => Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(tr("Unable to decode image")),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr("Close")),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      _openingAttachment = false;
      await preview?.evict();
    }
  }

  Future<void> _compose() async {
    await Navigator.of(context).push(
      MessageRoute<void>(
        builder: (_) => MmsComposer(repository: widget.repository),
      ),
    );
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr("MMS messages")),
      actions: [
        IconButton(
          tooltip: tr("Retry pending downloads"),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await widget.repository.invoke('retryMms');
                    await _load();
                  } catch (error) {
                    if (mounted) setState(() => _error = messageError(error));
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _compose,
      label: Text(tr("Compose MMS")),
      icon: const Icon(Icons.edit_outlined),
    ),
    body: Column(
      children: [
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _messages.length + 1,
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return Center(
                    child: _more
                        ? TextButton(
                            onPressed: () => _load(older: true),
                            child: Text(tr("Load more")),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              _messages.isEmpty
                                  ? tr("No MMS messages")
                                  : tr("All messages loaded"),
                            ),
                          ),
                  );
                }
                final message = _messages[index];
                final attachments = message['attachments'] as List;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message['address'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if ((message['subject'] as String).isNotEmpty)
                          Text(message['subject'] as String),
                        SelectableText(message['body'] as String),
                        if (message['pending'] == true)
                          Text(
                            tr("Waiting to download. Use Retry to try again."),
                          ),
                        Wrap(
                          spacing: 8,
                          children: attachments.map((item) {
                            final attachment = item as Map;
                            return ActionChip(
                              avatar: const Icon(Icons.attachment, size: 18),
                              label: Text(attachment['name'] as String),
                              onPressed: () => _preview(attachment),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${messageTime(message['date'] as int)} · ${switch (message['type']) {
                            1 => tr('Received'),
                            2 => tr('Sent'),
                            5 => tr('Failed to send'),
                            _ => tr('Sending'),
                          }}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class MmsComposer extends StatefulWidget {
  const MmsComposer({super.key, required this.repository});
  final MessageRepository repository;
  @override
  State<MmsComposer> createState() => _MmsComposerState();
}

class _MmsComposerState extends State<MmsComposer> {
  final _recipients = TextEditingController(), _body = TextEditingController();
  List<MessageRecord> _sims = [];
  int? _sim;
  String? _error;
  bool _sending = false;
  Map? _attachment;
  @override
  void initState() {
    super.initState();
    _loadSims();
  }

  Future<void> _loadSims() async {
    try {
      final sims = await widget.repository.records('subscriptions');
      if (mounted) {
        setState(() {
          _sims = sims;
          if (sims.length == 1) _sim = sims.first['id'] as int;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_sims.length > 1 && _sim == null) {
      setState(() => _error = tr("Choose a SIM card"));
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.repository.invoke('sendMms', {
        'recipients': _recipients.text
            .split(RegExp('[,，;；]'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(),
        'body': _body.text,
        'subscriptionId': _sim,
        'attachment': _attachment?['uri'],
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _recipients.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr("New MMS"))),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          tr(
            "MMS supports multiple recipients. Carrier charges may apply. Keep mobile data available.",
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _recipients,
          enabled: !_sending,
          decoration: InputDecoration(
            labelText: tr("Recipient numbers, separated by commas"),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _body,
          enabled: !_sending,
          minLines: 4,
          maxLines: 12,
          maxLength: 10000,
          decoration: InputDecoration(labelText: tr("MMS text")),
        ),
        DropdownMenu<int>(
          expandedInsets: EdgeInsets.zero,
          requestFocusOnTap: false,
          enabled: !_sending,
          initialSelection: _sim,
          label: Text(tr('Select SIM card')),
          dropdownMenuEntries: [
            for (final sim in _sims)
              DropdownMenuEntry(
                value: sim['id'] as int,
                label: 'SIM ${sim['slot']} ? ${sim['name']}',
              ),
          ],
          onSelected: (value) => setState(() => _sim = value),
        ),
        OutlinedButton.icon(
          onPressed: _sending
              ? null
              : () async {
                  try {
                    final attachment = await widget.repository.invoke<Map>(
                      'pickAttachment',
                    );
                    if (mounted && attachment != null) {
                      setState(() => _attachment = attachment);
                    }
                  } catch (error) {
                    if (mounted) setState(() => _error = messageError(error));
                  }
                },
          icon: const Icon(Icons.attach_file),
          label: Text(
            _attachment == null
                ? tr("Add image, audio or video")
                : tr("Selected: {p0}", [_attachment!['type']]),
          ),
        ),
        if (_attachment != null)
          TextButton(
            onPressed: _sending
                ? null
                : () => setState(() => _attachment = null),
            child: Text(tr("Remove attachment")),
          ),
        if (_error != null) Text(_error!),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send_outlined),
          label: Text(_sending ? tr("Submitting\u2026") : tr("Send MMS")),
        ),
      ],
    ),
  );
}
