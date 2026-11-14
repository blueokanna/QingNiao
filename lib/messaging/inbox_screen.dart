import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/message_theme.dart';
import '../src/rust/api/message_analysis.dart';
import 'message_repository.dart';
import 'conversation_screen.dart';
import 'trash_screen.dart';
import 'mms_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.repository = const MessageRepository()});
  final MessageRepository repository;
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  List<MessageRecord> _threads = [];
  List<MessageInsight> _insights = [];
  StreamSubscription<String>? _subscription;
  Timer? _searchTimer;
  bool _refreshing = false, _refreshAgain = false;
  bool _access = false, _loading = true, _requesting = false;
  String? _error;
  String _query = '', _filter = 'all';
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.repository.changes.listen(
      (event) {
        if (event == 'intent') {
          _openIntent();
        } else {
          _load();
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = messageError(error));
      },
    );
    _load().then((_) => _openIntent());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    final generation = ++_generation;
    try {
      final access = await widget.repository.hasAccess();
      final threads = access
          ? await widget.repository.records('conversations', {'query': _query})
          : <MessageRecord>[];
      final insights = await analyzeMessages(
        bodies: threads.map((row) => row['body'] as String).toList(),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _access = access;
        _threads = threads;
        _insights = insights;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = messageError(error);
        });
      }
    } finally {
      _refreshing = false;
      if (_refreshAgain && mounted) {
        _refreshAgain = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _openIntent() async {
    try {
      final data = await widget.repository.invoke<Map>('launchIntent');
      final address = data?['address'] as String?;
      if (mounted && address != null && address.isNotEmpty) {
        final matches = _threads.where((row) => row['address'] == address);
        _open(
          address: address,
          thread: matches.isEmpty ? null : matches.first['threadId'] as int,
          body: data?['body'] as String?,
        );
      }
    } catch (_) {}
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    try {
      await widget.repository.invoke('requestAccess');
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _open({String address = '', int? thread, String? body}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          repository: widget.repository,
          address: address,
          threadId: thread,
          initialBody: body,
        ),
      ),
    );
    await _load();
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _searchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = <int>[];
    for (var index = 0; index < _threads.length; index++) {
      final thread = _threads[index];
      if (_filter == 'unread' && thread['unread'] == 0) continue;
      if (_filter == 'verification' &&
          _insights[index].category != 'verification') {
        continue;
      }
      visible.add(index);
    }
    return Scaffold(
      floatingActionButton: _access
          ? FloatingActionButton.extended(
              onPressed: () => _open(),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('写短信'),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                title: const Text(
                  '青鸟',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                actions: [
                  IconButton(
                    tooltip: '回收站',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: !_access
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    TrashScreen(repository: widget.repository),
                              ),
                            );
                            _load();
                          },
                  ),
                  IconButton(
                    tooltip: '应用权限',
                    onPressed: () async {
                      try {
                        await widget.repository.invoke('settings');
                      } catch (error) {
                        if (mounted) {
                          setState(() => _error = messageError(error));
                        }
                      }
                    },
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
              if (_access)
                SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              MmsScreen(repository: widget.repository),
                        ),
                      ),
                      icon: const Icon(Icons.perm_media_outlined),
                      label: const Text('彩信与群组'),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '让重要的消息\n自然抵达。',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${_threads.length} 个会话 · ${_threads.fold<int>(0, (sum, row) => sum + (row['unread'] as int))} 条未读',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        onChanged: (value) {
                          _query = value;
                          _searchTimer?.cancel();
                          _searchTimer = Timer(
                            const Duration(milliseconds: 250),
                            _load,
                          );
                        },
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: '搜索号码或全部短信正文',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            [
                                  ('all', '全部'),
                                  ('unread', '未读'),
                                  ('verification', '验证码'),
                                ]
                                .map(
                                  (item) => FilterChip(
                                    label: Text(item.$2),
                                    selected: _filter == item.$1,
                                    onSelected: (_) =>
                                        setState(() => _filter = item.$1),
                                    showCheckmark: false,
                                  ),
                                )
                                .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(_error!),
                        TextButton(onPressed: _load, child: const Text('重新加载')),
                      ],
                    ),
                  ),
                ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!_loading && !_access)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.mark_chat_read_outlined, size: 42),
                            const SizedBox(height: 20),
                            Text(
                              '连接手机短信',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            const Text('设为默认短信应用后，读取和接收手机上的真实消息。短信分析在本机完成。'),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _requesting ? null : _request,
                              child: Text(_requesting ? '等待系统授权…' : '设置默认短信应用'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (!_loading && _access && visible.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('这里暂时没有消息')),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, position) {
                    final index = visible[position];
                    final thread = _threads[index];
                    final insight = _insights[index];
                    final unread = thread['unread'] as int;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: unread > 0
                            ? colors.secondaryContainer.withValues(alpha: .45)
                            : colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(28),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _open(
                            address: thread['address'] as String,
                            thread: thread['threadId'] as int,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Hero(
                                  tag: 'thread-${thread['threadId']}',
                                  child: SenderAvatar(
                                    address: thread['address'] as String,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              thread['address'] as String,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: unread > 0
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            messageTime(thread['date'] as int),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        thread['body'] as String,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                          height: 1.45,
                                        ),
                                      ),
                                      if (insight.verificationCode != null)
                                        ActionChip(
                                          avatar: const Icon(
                                            Icons.copy_rounded,
                                            size: 16,
                                          ),
                                          label: Text(
                                            insight.verificationCode!,
                                          ),
                                          onPressed: () async {
                                            await Clipboard.setData(
                                              ClipboardData(
                                                text: insight.verificationCode!,
                                              ),
                                            );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                    const SnackBar(
                                                      content: Text('验证码已复制'),
                                                    ),
                                                  );
                                            }
                                          },
                                        ),
                                      if (unread > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Badge(
                                            label: Text('$unread'),
                                            backgroundColor: colors.primary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 110)),
            ],
          ),
        ),
      ),
    );
  }
}
