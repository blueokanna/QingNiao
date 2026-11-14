import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import 'format.dart';
import 'message_hub.dart';
import 'message_repository.dart';
import 'message_widgets.dart';
import 'models.dart';
import 'trash_screen.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.repository,
    required this.hub,
    required this.thread,
  });

  final MessageRepository repository;
  final MessageHub hub;
  final ThreadSummary thread;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _body = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  List<SmsMessage> _messages = const [];
  List<SimCard> _sims = const [];
  final Set<int> _selected = {};
  StreamSubscription<String>? _changes;
  Timer? _draftTimer;
  AttachmentChoice? _attachment;
  int? _simId;
  bool _loading = true;
  bool _sending = false;
  bool _more = true;
  bool _paging = false;
  bool _showJump = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _body.addListener(_onComposerChanged);
    _scroll.addListener(_onScroll);
    _initialize();
    _changes = widget.repository.changes.listen((event) {
      if (event != 'intent') _load(silent: true);
    });
  }

  Future<void> _initialize() async {
    try {
      final sims = await widget.repository.subscriptions();
      final draft = await widget.repository.draft(widget.thread.address);
      if (!mounted) return;
      setState(() {
        _sims = sims;
        if (sims.length == 1) _simId = sims.first.id;
        if (draft != null && draft.isNotEmpty && _body.text.isEmpty) _body.text = draft;
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = messageError(error);
      });
    }
  }

  void _onComposerChanged() {
    if (mounted) setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      await widget.repository.saveDraft(widget.thread.address, _body.text);
    } catch (_) {}
  }

  void _onScroll() {
    final shouldShow = _scroll.hasClients && _scroll.offset > 260;
    if (shouldShow != _showJump && mounted) setState(() => _showJump = shouldShow);
  }

  Future<void> _load({bool silent = false, bool older = false}) async {
    if (older && (_paging || !_more)) return;
    if (older) setState(() => _paging = true);
    try {
      final rows = await widget.repository.messages(
        threadId: widget.thread.threadId,
        before: older && _messages.isNotEmpty ? _messages.first.id : null,
        limit: 80,
      );
      final analyzed = await widget.repository.analyzeMessages(rows);
      if (!mounted) return;
      setState(() {
        _messages = older ? [...analyzed, ..._messages] : analyzed;
        _more = rows.length >= 80;
        _loading = false;
        _paging = false;
        _error = null;
      });
      if (analyzed.any((message) => !message.read)) {
        await widget.repository.markRead(widget.thread.threadId);
        widget.hub.refresh(silent: true);
      }
      if (!older && !silent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(0);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _paging = false;
        _error = messageError(error);
      });
    }
  }

  Future<void> _send() async {
    final body = _body.text.trim();
    if (_sending || (body.isEmpty && _attachment == null)) return;
    final settings = AppScope.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final signature = settings.signature.trim();
      final full = signature.isEmpty || body.isEmpty ? body : '$body\n\n$signature';
      if (_attachment != null) {
        await widget.repository.sendMms(
          recipients: [widget.thread.address],
          body: full,
          subscriptionId: _simId,
          attachment: _attachment!.uri,
        );
      } else {
        await widget.repository.send(
          address: widget.thread.address,
          body: full,
          subscriptionId: _simId,
        );
      }
      if (!mounted) return;
      _body.clear();
      setState(() => _attachment = null);
      await _saveDraft();
      await _load(silent: true);
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutQuint,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _schedule() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      showAuroraSnack(context, '先写下要定时发送的内容', icon: Icons.schedule_rounded);
      return;
    }
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (at.isBefore(DateTime.now())) {
      showAuroraSnack(context, '请选择一个未来的时间');
      return;
    }
    try {
      await widget.repository.schedule(
        address: widget.thread.address,
        body: body,
        at: at.millisecondsSinceEpoch,
        subscriptionId: _simId,
      );
      _body.clear();
      await _saveDraft();
      if (mounted) {
        showAuroraSnack(
          context,
          '将在 ${MessageFormat.dateTime(at.millisecondsSinceEpoch)} 发送',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final attachment = await widget.repository.pickAttachment();
      if (attachment != null && mounted) setState(() => _attachment = attachment);
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    }
  }

  Future<void> _pickSim() async {
    if (_sims.length < 2) return;
    final selected = await showAuroraSheet<int>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final sim in _sims)
            AuroraSettingTile(
              title: sim.label,
              subtitle: sim.carrier.isEmpty ? '发送号码' : sim.carrier,
              icon: Icons.sim_card_outlined,
              trailing: sim.id == _simId
                  ? Icon(Icons.check_circle_rounded, color: context.colors.primary, size: 20)
                  : null,
              onTap: () => Navigator.pop(context, sim.id),
            ),
        ],
      ),
    );
    if (selected != null) setState(() => _simId = selected);
  }

  // ignore: unused_element
  Future<void> _messageActions(SmsMessage message) async {
    if (_selected.isNotEmpty) {
      setState(() {
        if (!_selected.add(message.id)) _selected.remove(message.id);
      });
      return;
    }
    final action = await showAuroraSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuroraSettingTile(
            title: '复制正文',
            icon: Icons.copy_rounded,
            onTap: () => Navigator.pop(context, 'copy'),
          ),
          AuroraSettingTile(
            title: '转发到输入框',
            icon: Icons.forward_to_inbox_outlined,
            onTap: () => Navigator.pop(context, 'forward'),
          ),
          AuroraSettingTile(
            title: '查看详情',
            icon: Icons.info_outline_rounded,
            onTap: () => Navigator.pop(context, 'details'),
          ),
          if (message.isFailed)
            AuroraSettingTile(
              title: '重新发送',
              icon: Icons.refresh_rounded,
              onTap: () => Navigator.pop(context, 'retry'),
            ),
          AuroraSettingTile(
            title: '移入回收站',
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onTap: () => Navigator.pop(context, 'trash'),
          ),
        ],
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
        if (mounted) showAuroraSnack(context, '已复制');
      case 'forward':
        _body.text = message.body;
      case 'details':
        _showDetails(message);
      case 'retry':
        _body.text = message.body;
        await _send();
      case 'trash':
        await widget.repository.hide(message.id);
        await _load(silent: true);
        widget.hub.refresh(silent: true);
        if (mounted) showAuroraSnack(context, '已移入回收站');
    }
  }

  void _showDetails(SmsMessage message) {
    showAuroraSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('消息详情', style: context.texts.headlineSmall),
            const SizedBox(height: 12),
            _detailRow(context, '类型', message.isMms ? '彩信 MMS' : '短信 SMS'),
            _detailRow(
              context,
              '状态',
              switch (message.delivery) {
                DeliveryState.delivered => '已送达',
                DeliveryState.sent => '已发送',
                DeliveryState.sending => '正在发送',
                DeliveryState.failed => '发送失败',
                DeliveryState.none => message.outgoing ? '已发送' : '已接收',
              },
            ),
            _detailRow(context, '时间', MessageFormat.fullDate(message.date)),
            _detailRow(context, '号码', message.address),
            if (message.sender.isNotEmpty) _detailRow(context, '发送者', message.sender),
            if (message.subscriptionId >= 0)
              _detailRow(context, 'SIM', 'SIM ${message.subscriptionId}'),
            _detailRow(context, '编码', MessageFormat.segment(message.body).encoding),
            _detailRow(context, '字数', '${message.body.length}'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: context.texts.bodyMedium)),
        ],
      ),
    );
  }

  Future<void> _headerActions() async {
    final action = await showAuroraSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuroraSettingTile(
            title: '会话详情',
            subtitle: '${MessageFormat.phone(widget.thread.address)} · ${_messages.length} 条已加载',
            icon: Icons.info_outline_rounded,
            onTap: () => Navigator.pop(context, 'details'),
          ),
          AuroraSettingTile(
            title: '屏蔽此号码',
            icon: Icons.block_rounded,
            onTap: () => Navigator.pop(context, 'block'),
          ),
          AuroraSettingTile(
            title: '归档会话',
            icon: Icons.archive_outlined,
            onTap: () => Navigator.pop(context, 'archive'),
          ),
          AuroraSettingTile(
            title: '打开回收站',
            icon: Icons.delete_outline_rounded,
            onTap: () => Navigator.pop(context, 'trash'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'block':
        await widget.hub.block(widget.thread.address);
        if (mounted) showAuroraSnack(context, '已屏蔽此号码');
      case 'archive':
        await widget.hub.archive(widget.thread.threadId, true);
        if (mounted) Navigator.maybePop(context);
      case 'trash':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrashScreen(repository: widget.repository),
          ),
        );
      case 'details':
        showAuroraSheet<void>(
          context: context,
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('会话详情', style: context.texts.headlineSmall),
              const SizedBox(height: 12),
              _detailRow(context, '号码', widget.thread.address),
              _detailRow(context, '名称', widget.thread.title),
              _detailRow(context, '会话 ID', '${widget.thread.threadId}'),
              _detailRow(context, '消息数', '${_messages.length}'),
            ],
          ),
        );
    }
  }

  Future<void> _bulkCopy() async {
    final count = _selected.length;
    final text = _messages
        .where((message) => _selected.contains(message.id))
        .map((message) => message.body)
        .where((body) => body.isNotEmpty)
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _selected.clear());
    showAuroraSnack(context, '已复制 $count 条');
  }

  Future<void> _bulkDelete() async {
    final count = _selected.length;
    final confirmed = await showAuroraDialog<bool>(
      context: context,
      title: Text('移入回收站 $count 条消息？'),
      content: const Text('可以在回收站中恢复，保留期结束后自动清理。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('移入回收站')),
      ],
    );
    if (confirmed != true) return;
    for (final id in _selected) {
      await widget.repository.hide(id);
    }
    setState(() => _selected.clear());
    await _load(silent: true);
    widget.hub.refresh(silent: true);
  }

  Future<void> _openAttachment(Attachment attachment) async {
    final bytes = await widget.repository.attachmentData(attachment.uri);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .8),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: bytes == null
                    ? AspectRatio(
                        aspectRatio: 4 / 3,
                        child: ColoredBox(
                          color: context.colors.surfaceContainerHigh,
                          child: Center(
                            child: Text(attachment.name, style: context.texts.bodyMedium),
                          ),
                        ),
                      )
                    : InteractiveViewer(
                        child: Image.memory(
                          bytes,
                          cacheWidth: 1600,
                          errorBuilder: (_, _, _) => Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text('无法解码图片：${attachment.name}'),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            AuroraIconButton(
              icon: Icons.close_rounded,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveDraft();
    _body.removeListener(_onComposerChanged);
    _scroll.removeListener(_onScroll);
    _draftTimer?.cancel();
    _changes?.cancel();
    _body.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    final selection = _selected.isNotEmpty;
    return AuroraScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: selection
                  ? _selectionBar(context)
                  : AuroraTopBar(
                      key: const ValueKey('header'),
                      leading: AuroraAvatar(
                        seed: widget.thread.address,
                        size: 40,
                        label: widget.thread.title,
                        heroTag: 'thread-avatar-${widget.thread.threadId}',
                        icon: widget.thread.isGroup ? Icons.groups_2_rounded : null,
                      ),
                      title: widget.thread.title,
                      subtitle: widget.thread.isGroup
                          ? '${widget.thread.recipients.length} 位收件人'
                          : MessageFormat.phone(widget.thread.address),
                      actions: [
                        AuroraIconButton(
                          icon: Icons.more_horiz_rounded,
                          tooltip: '会话操作',
                          onPressed: _headerActions,
                        ),
                      ],
                    ),
            ),
            if (_error != null)
              AuroraErrorBanner(message: _error!, onRetry: () => _load()),
            Expanded(
              child: Stack(
                children: [
                  if (_loading)
                    const Center(child: AuroraLoading())
                  else if (_messages.isEmpty)
                    const Center(
                      child: AuroraEmpty(
                        title: '从一句问候开始',
                        message: '这段对话还没有消息。',
                        icon: Icons.waving_hand_outlined,
                        size: 108,
                      ),
                    )
                  else
                    ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      itemCount: entries.length + (_more ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_more && index == entries.length) {
                          return Center(
                            child: TextButton(
                              onPressed: _paging ? null : () => _load(older: true),
                              child: Text(_paging ? '正在加载…' : '加载更早的消息'),
                            ),
                          );
                        }
                        final entry = entries[entries.length - 1 - index];
                        if (entry.day != null) {
                          return DayDivider(
                            key: ValueKey('day-${entry.day}'),
                            millis: entry.day!,
                          );
                        }
                        final message = entry.message!;
                        return MessageBubble(
                          key: ValueKey('message-${message.id}'),
                          message: message,
                          groupedTop: entry.groupedTop,
                          groupedBottom: entry.groupedBottom,
                          selected: _selected.contains(message.id),
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              if (_selected.isEmpty) {
                                _selected.add(message.id);
                              } else if (!_selected.add(message.id)) {
                                _selected.remove(message.id);
                              }
                            });
                          },
                          onRetry: message.isFailed
                              ? () {
                                  _body.text = message.body;
                                  _send();
                                }
                              : null,
                          onOpenLink: (url) => widget.repository.openUrl(url),
                          onOpenAttachment: _openAttachment,
                        );
                      },
                    ),
                  if (_showJump && !_loading && _messages.isNotEmpty)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: AuroraIconButton(
                        icon: Icons.keyboard_double_arrow_down_rounded,
                        tooltip: '回到底部',
                        onPressed: () => _scroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 360),
                          curve: Curves.easeOutQuint,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_attachment != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    Icon(
                      _attachment!.mime.startsWith('image/')
                          ? Icons.image_outlined
                          : Icons.attach_file_rounded,
                      size: 16,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _attachment!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.labelSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: '移除附件',
                      onPressed: () => setState(() => _attachment = null),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            AnimatedBuilder(
              animation: _body,
              builder: (context, _) => MessageComposer(
                controller: _body,
                focusNode: _focus,
                segment: MessageFormat.segment(_body.text),
                sending: _sending,
                enabled: !selection,
                onSend: _send,
                onAttach: _pickAttachment,
                onSchedule: _schedule,
                onPickSim: _pickSim,
                simLabel: _simLabel(),
                attachments: _attachment == null ? 0 : 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _simLabel() {
    if (_sims.isEmpty) return null;
    SimCard? sim;
    for (final item in _sims) {
      if (item.id == _simId) {
        sim = item;
        break;
      }
    }
    return sim == null ? '选择 SIM' : 'SIM ${sim.slot} · ${sim.name}';
  }

  Widget _selectionBar(BuildContext context) {
    return AuroraTopBar(
      key: const ValueKey('selection'),
      showBack: false,
      leading: AuroraIconButton(
        icon: Icons.close_rounded,
        onPressed: () => setState(() => _selected.clear()),
      ),
      title: '已选 ${_selected.length} 条',
      subtitle: '复制或移入回收站',
      actions: [
        AuroraIconButton(
          icon: Icons.copy_rounded,
          tooltip: '复制',
          onPressed: _selected.isEmpty ? null : _bulkCopy,
        ),
        const SizedBox(width: 4),
        AuroraIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: '移入回收站',
          onPressed: _selected.isEmpty ? null : _bulkDelete,
          color: context.colors.error,
        ),
      ],
    );
  }

  List<_Entry> _entries() {
    final entries = <_Entry>[];
    SmsMessage? previous;
    for (var index = 0; index < _messages.length; index++) {
      final message = _messages[index];
      final next = index + 1 < _messages.length ? _messages[index + 1] : null;
      final sameDay = previous != null && _sameDay(previous.date, message.date);
      if (!sameDay) entries.add(_Entry.day(message.date));
      final groupedTop = sameDay &&
          previous.outgoing == message.outgoing &&
          message.date - previous.date < 4 * 60 * 1000;
      final groupedBottom = next != null &&
          _sameDay(next.date, message.date) &&
          next.outgoing == message.outgoing &&
          next.date - message.date < 4 * 60 * 1000;
      entries.add(
        _Entry.message(message, groupedTop: groupedTop, groupedBottom: groupedBottom),
      );
      previous = message;
    }
    return entries;
  }

  bool _sameDay(int a, int b) {
    final first = DateTime.fromMillisecondsSinceEpoch(a);
    final second = DateTime.fromMillisecondsSinceEpoch(b);
    return first.year == second.year && first.month == second.month && first.day == second.day;
  }
}

class _Entry {
  const _Entry.day(this.day) : message = null, groupedTop = false, groupedBottom = false;
  const _Entry.message(this.message, {required this.groupedTop, required this.groupedBottom})
    : day = null;

  final int? day;
  final SmsMessage? message;
  final bool groupedTop;
  final bool groupedBottom;
}
