import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/message_theme.dart';
import 'message_repository.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.repository,
    required this.address,
    this.threadId,
    this.initialBody,
  });
  final MessageRepository repository;
  final String address;
  final int? threadId;
  final String? initialBody;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _address = TextEditingController(
    text: widget.address,
  );
  final _body = TextEditingController();
  List<MessageRecord> _messages = [], _sims = [];
  StreamSubscription<String>? _changes;
  Timer? _draftTimer;
  int? _thread, _sim;
  int _generation = 0;
  bool _sending = false, _loading = true, _more = true, _paging = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _thread = widget.threadId;
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.repository.changes.listen(
      (_) => _load(),
      onError: (Object error) {
        if (mounted) setState(() => _error = messageError(error));
      },
    );
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final sims = await widget.repository.records('subscriptions');
      final draft =
          widget.initialBody ??
          await widget.repository.invoke<String>('draft', {
            'address': widget.address,
          }) ??
          '';
      if (!mounted) return;
      setState(() {
        _sims = sims;
        if (sims.length == 1) _sim = sims.first['id'] as int;
        if (_body.text.isEmpty) _body.text = draft;
      });
      _body.addListener(_scheduleDraft);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = messageError(error);
          _loading = false;
        });
      }
    }
  }

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 450), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (_address.text.trim().isEmpty) return;
    try {
      await widget.repository.invoke('saveDraft', {
        'address': _address.text.trim(),
        'body': _body.text,
      });
    } catch (error) {
      if (mounted) setState(() => _error = '草稿未保存：${messageError(error)}');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _saveDraft();
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load({bool older = false}) async {
    if (older && (_paging || !_more)) return;
    final generation = ++_generation;
    if (older) setState(() => _paging = true);
    try {
      if (_thread == null && _address.text.trim().isNotEmpty) {
        final conversations = await widget.repository.records('conversations');
        final found = conversations.where(
          (row) => row['address'] == _address.text.trim(),
        );
        if (found.isNotEmpty) _thread = found.first['threadId'] as int;
      }
      final rows = _thread == null
          ? <MessageRecord>[]
          : await widget.repository.records('messages', {
              'threadId': _thread,
              if (older && _messages.isNotEmpty) 'before': _messages.last['id'],
            });
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages = older ? [..._messages, ...rows] : rows;
        _more = rows.length == 100;
        _loading = false;
        _paging = false;
        _error = null;
      });
      if (_thread != null &&
          rows.any((row) => row['read'] == false) &&
          ModalRoute.of(context)?.isCurrent == true) {
        await widget.repository.invoke('markRead', {'threadId': _thread});
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = messageError(error);
          _loading = false;
          _paging = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (_sending || _body.text.trim().isEmpty) return;
    if (_sims.length > 1 && _sim == null) {
      setState(() => _error = '请选择发送 SIM 卡');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    _draftTimer?.cancel();
    final sentBody = _body.text;
    try {
      await _saveDraft();
      await widget.repository.invoke('send', {
        'address': _address.text.trim(),
        'body': sentBody,
        'subscriptionId': _sim,
      });
      if (!mounted) return;
      if (_body.text == sentBody) _body.clear();
      await _saveDraft();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _messageActions(MessageRecord message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制正文'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移入回收站'),
              subtitle: const Text('可随时恢复；仍保留在系统短信库中'),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
          ],
        ),
      ),
    );
    try {
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: message['body'] as String));
      }
      if (action == 'hide') {
        await widget.repository.invoke('hide', {'id': message['id']});
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    }
  }

  @override
  void dispose() {
    _saveDraft();
    ++_generation;
    _draftTimer?.cancel();
    _changes?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _body.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (widget.threadId != null) ...[
              Hero(
                tag: 'thread-${widget.threadId}',
                child: SenderAvatar(address: widget.address, size: 40),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                widget.address.isEmpty ? '新的短信' : widget.address,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.address.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _address,
                  enabled: !_sending,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: '收件号码',
                    suffixIcon: IconButton(
                      tooltip: '选择联系人',
                      icon: const Icon(Icons.person_add_alt_outlined),
                      onPressed: _sending
                          ? null
                          : () async {
                              try {
                                final phone = await widget.repository
                                    .invoke<String>('pickContact');
                                if (mounted && phone != null)
                                  _address.text = phone;
                              } catch (error) {
                                if (mounted)
                                  setState(() => _error = messageError(error));
                              }
                            },
                    ),
                  ),
                ),
              ),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(onPressed: () => _load(), child: const Text('重试')),
                ],
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                  ? const Center(child: Text('从一句问候开始'))
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(20),
                      itemCount: _messages.length + (_more ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return TextButton(
                            onPressed: _paging
                                ? null
                                : () => _load(older: true),
                            child: Text(_paging ? '正在加载…' : '加载更早消息'),
                          );
                        }
                        final message = _messages[index];
                        final outgoing = message['type'] != 1;
                        final status = switch (message['type']) {
                          5 => '发送失败',
                          4 || 6 => '正在发送',
                          2 =>
                            message['status'] == 0
                                ? '已送达'
                                : message['status'] == 64
                                ? '送达失败'
                                : '已发送',
                          _ => '',
                        };
                        return Align(
                          alignment: outgoing
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: 12,
                                left: outgoing ? 32 : 0,
                                right: outgoing ? 0 : 32,
                              ),
                              child: Material(
                                color: outgoing
                                    ? colors.primaryContainer
                                    : colors.surfaceContainerHigh,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(24),
                                    topRight: const Radius.circular(24),
                                    bottomLeft: Radius.circular(
                                      outgoing ? 24 : 6,
                                    ),
                                    bottomRight: Radius.circular(
                                      outgoing ? 6 : 24,
                                    ),
                                  ),
                                ),
                                child: InkWell(
                                  onLongPress: () => _messageActions(message),
                                  borderRadius: BorderRadius.circular(24),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          message['body'] as String,
                                          style: TextStyle(
                                            height: 1.5,
                                            fontSize: 16,
                                            color: outgoing
                                                ? colors.onPrimaryContainer
                                                : colors.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${messageTime(message['date'] as int)}  $status',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                        if (message['type'] == 5)
                                          TextButton(
                                            onPressed: () {
                                              _body.text =
                                                  message['body'] as String;
                                            },
                                            child: const Text('编辑后重发'),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_sims.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Text('发送号码'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _sim,
                        hint: const Text('选择 SIM 卡'),
                        items: _sims
                            .map(
                              (sim) => DropdownMenuItem<int>(
                                value: sim['id'] as int,
                                child: Text(
                                  'SIM ${sim['slot']} · ${sim['name']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _sending
                            ? null
                            : (value) => setState(() => _sim = value),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _body,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 10000,
                      decoration: const InputDecoration(
                        hintText: '写下你的消息',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '发送短信',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
