import 'package:flutter/material.dart';

import 'message_repository.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, required this.repository});
  final MessageRepository repository;
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<MessageRecord> _messages = [];
  String? _error;
  bool _busy = false, _more = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool older = false}) async {
    try {
      final rows = await widget.repository.records('messages', {
        'trash': true,
        if (older && _messages.isNotEmpty) 'before': _messages.last['id'],
      });
      if (mounted) {
        setState(() {
          _messages = older ? [..._messages, ...rows] : rows;
          _more = rows.length == 100;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    }
  }

  Future<void> _act(MessageRecord message, String action) async {
    if (_busy) return;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('永久删除这条短信？'),
          content: const Text('将从系统短信库删除，无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('永久删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.invoke(action, {'id': message['id']});
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('回收站')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('回收站中的短信保留在系统消息库，仅在青鸟中隐藏。不会自动清空。'),
        ),
        if (_error != null) Text(_error!),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              itemCount: _messages.length + 1,
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return Center(
                    child: _more
                        ? TextButton(
                            onPressed: () => _load(older: true),
                            child: const Text('加载更多'),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_messages.isEmpty ? '回收站是空的' : '已显示全部'),
                          ),
                  );
                }
                final message = _messages[index];
                return Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message['address'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message['body'] as String,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _act(message, 'restore'),
                              child: const Text('恢复'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _act(message, 'delete'),
                              child: const Text('永久删除'),
                            ),
                          ],
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
