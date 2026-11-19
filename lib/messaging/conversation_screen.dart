import 'read_receipt_observer.dart';
import '../messaging/sensitive_clipboard.dart';

import 'package:qingniao/l10n/app_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_motion.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import 'format.dart';
import 'message_hub.dart';
import 'message_repository.dart';
import 'message_widgets.dart';
import 'models.dart';
import 'sim_identity.dart';
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

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final TextEditingController _body = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  List<SmsMessage> _messages = const [];
  List<SimCard> _sims = const [];
  final Set<int> _selected = {};
  final Set<int> _unreadCodeIds = {};
  StreamSubscription<String>? _changes;
  Timer? _draftTimer;
  Timer? _changeTimer;
  Future<void>? _loadFuture;
  bool _reloadQueued = false;
  AttachmentChoice? _attachment;
  int? _simId;
  int _simGeneration = 0;
  bool _loading = true;
  bool _sending = false;
  bool _openingAttachment = false;
  bool _more = true;
  bool _paging = false;
  int _loadGeneration = 0;
  bool _showJump = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _body.addListener(_onComposerChanged);
    _scroll.addListener(_onScroll);
    _initialize();
    _changes = widget.repository.changes.listen(
      (event) {
        if (event == 'intent' || event == 'sync' || !_foreground) return;
        _changeTimer ??= Timer(const Duration(milliseconds: 120), () {
          _changeTimer = null;
          unawaited(_load(silent: true));
        });
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = messageError(error));
      },
    );
  }

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSims());
      unawaited(_load(silent: true));
    } else {
      _changeTimer?.cancel();
      _changeTimer = null;
      // Invalidate a pending query before it can mark background messages read.
      _loadGeneration++;
      _draftTimer?.cancel();
      unawaited(_saveDraft());
      if (_paging) setState(() => _paging = false);
    }
  }

  Future<void> _initialize() async {
    try {
      await _refreshSims();
      final draft = await widget.repository.draft(widget.thread.address);
      if (!mounted) return;
      setState(() {
        if (draft != null && draft.isNotEmpty && _body.text.isEmpty) {
          _body.text = draft;
        }
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

  Future<void> _refreshSims() async {
    final generation = ++_simGeneration;
    try {
      final sims = await widget.repository.subscriptions();
      if (!mounted || generation != _simGeneration) return;
      setState(() {
        _sims = sims;
        if (!sims.any((sim) => sim.id == _simId)) {
          _simId = sims.length == 1 ? sims.first.id : null;
        }
      });
    } catch (_) {
      if (mounted && generation == _simGeneration) {
        setState(() {
          _sims = const [];
          _simId = null;
        });
      }
    }
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    if (AuroraMotion.isReduced(context)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(
        0,
        duration: AuroraMotion.page,
        curve: AuroraMotion.decelerate,
      );
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
    if (shouldShow != _showJump && mounted) {
      setState(() => _showJump = shouldShow);
    }
  }

  Future<void> _load({bool silent = false, bool older = false}) {
    if (!mounted || !_foreground || (older && !_more)) {
      return Future<void>.value();
    }
    _changeTimer?.cancel();
    _changeTimer = null;
    if (_loadFuture != null) {
      if (!older) _reloadQueued = true;
      return _loadFuture!;
    }
    final completion = Completer<void>();
    _loadFuture = completion.future;
    unawaited(_drainLoads(completion, silent: silent, older: older));
    return completion.future;
  }

  Future<void> _drainLoads(
    Completer<void> completion, {
    required bool silent,
    required bool older,
  }) async {
    try {
      await _loadOnce(silent: silent, older: older);
      while (_reloadQueued && mounted && _foreground) {
        _reloadQueued = false;
        await _loadOnce(silent: true);
      }
    } finally {
      _loadFuture = null;
      _reloadQueued = false;
      completion.complete();
    }
  }

  Future<void> _loadOnce({bool silent = false, bool older = false}) async {
    if (!mounted || !_foreground || (older && (_paging || !_more))) return;
    final generation = ++_loadGeneration;
    if (older) setState(() => _paging = true);
    try {
      final rows = await widget.repository.messages(
        threadId: widget.thread.threadId,
        before: older && _messages.isNotEmpty ? _messages.first.id : null,
        beforeDate: older && _messages.isNotEmpty ? _messages.first.date : null,
        limit: 80,
      );
      if (!mounted || !_foreground || generation != _loadGeneration) return;
      final analyzed = await widget.repository.analyzeMessages(rows);
      if (!mounted || !_foreground || generation != _loadGeneration) return;
      _unreadCodeIds.addAll(
        analyzed
            .where((m) => !m.read && !m.outgoing && m.hasOtp)
            .map((m) => m.id),
      );
      setState(() {
        _messages = older
            ? [...analyzed, ..._messages]
                  .fold<Map<int, SmsMessage>>(
                    {},
                    (map, message) => map..[message.id] = message,
                  )
                  .values
                  .toList()
            : analyzed;
        _more = rows.length >= 80;
        _loading = false;
        _paging = false;
        _error = null;
      });
      if ((ModalRoute.of(context)?.isCurrent ?? true) &&
          analyzed.any((message) => !message.read && !message.outgoing)) {
        await widget.repository.markRead(widget.thread.threadId);
        widget.hub.refresh(silent: true);
      }
      if (!older && !silent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(0);
        });
      }
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
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
      final full = signature.isEmpty || body.isEmpty
          ? body
          : '$body\n\n$signature';
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
      // Refreshing history can wait on unrelated provider work. Release the
      // editor as soon as the modem has accepted the submission.
      unawaited(_refreshAfterSend());
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refreshAfterSend() async {
    await _saveDraft();
    if (!mounted) return;
    await _load(silent: true);
    if (mounted) _jumpToLatest();
  }

  Future<void> _schedule() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      showAuroraSnack(
        context,
        tr("Write a message before scheduling it"),
        icon: Icons.schedule_rounded,
      );
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
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (at.isBefore(DateTime.now())) {
      showAuroraSnack(context, tr("Choose a future time"));
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
          tr("Scheduled for {p0}", [
            MessageFormat.dateTime(at.millisecondsSinceEpoch),
          ]),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageError(error));
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final attachment = await widget.repository.pickAttachment();
      if (attachment != null && mounted) {
        setState(() => _attachment = attachment);
      }
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    }
  }

  Future<void> _pickSim() async {
    await _refreshSims();
    if (!mounted || _sims.length < 2) return;
    final selected = await showAuroraSheet<int>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final sim in _sims)
            AuroraSettingTile(
              title: simCardLabel(sim),
              subtitle:
                  '${tr('Subscription ID')}: ${sim.id}'
                  '${sim.carrier.isEmpty ? '' : ' · ${sim.carrier}'}',
              icon: Icons.sim_card_outlined,
              trailing: sim.id == _simId
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: context.colors.primary,
                      size: 20,
                    )
                  : null,
              onTap: () => Navigator.pop(context, sim.id),
            ),
        ],
      ),
    );
    if (selected != null && mounted) setState(() => _simId = selected);
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
            title: tr("Copy text"),
            icon: Icons.copy_rounded,
            onTap: () => Navigator.pop(context, 'copy'),
          ),
          AuroraSettingTile(
            title: tr("Forward to composer"),
            icon: Icons.forward_to_inbox_outlined,
            onTap: () => Navigator.pop(context, 'forward'),
          ),
          AuroraSettingTile(
            title: tr("View details"),
            icon: Icons.info_outline_rounded,
            onTap: () => Navigator.pop(context, 'details'),
          ),
          if (message.isFailed)
            AuroraSettingTile(
              title: tr("Resend"),
              icon: Icons.refresh_rounded,
              onTap: () => Navigator.pop(context, 'retry'),
            ),
          AuroraSettingTile(
            title: tr("Move to trash"),
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
        await SensitiveClipboard.copy(message.body);
        if (mounted) showAuroraSnack(context, tr("Copied"));
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
        if (mounted) showAuroraSnack(context, tr("Moved to trash"));
    }
  }

  void _showDetails(SmsMessage message) {
    showAuroraSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr("Message details"), style: context.texts.headlineSmall),
            const SizedBox(height: 12),
            _detailRow(
              context,
              tr("Type"),
              message.isMms ? tr("MMS") : tr("SMS"),
            ),
            _detailRow(context, tr("Status"), switch (message.delivery) {
              DeliveryState.delivered => tr("Delivered"),
              DeliveryState.sent => tr("Sent"),
              DeliveryState.sending => tr("Sending"),
              DeliveryState.failed => tr("Failed to send"),
              DeliveryState.none =>
                message.outgoing ? tr("Sent") : tr("Received"),
            }),
            _detailRow(
              context,
              tr("Time"),
              MessageFormat.fullDate(message.date),
            ),
            _detailRow(context, tr("Number"), message.address),
            if (message.sender.isNotEmpty)
              _detailRow(context, tr("Sender"), message.sender),
            _detailRow(
              context,
              tr('SIM source'),
              MessageSimSource.resolve(message.subscriptionId, _sims).label,
            ),
            if (message.subscriptionId >= 0)
              _detailRow(
                context,
                tr('Subscription ID'),
                '${message.subscriptionId}',
              ),
            _detailRow(
              context,
              tr("Encoding"),
              MessageFormat.segment(message.body).encoding,
            ),
            _detailRow(
              context,
              tr("Character count"),
              '${message.body.length}',
            ),
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
            title: tr("Conversation details"),
            subtitle: tr("{p0} \u00b7 Loaded messages: {p1}", [
              MessageFormat.phone(widget.thread.address),
              _messages.length,
            ]),
            icon: Icons.info_outline_rounded,
            onTap: () => Navigator.pop(context, 'details'),
          ),
          AuroraSettingTile(
            title: tr("Block this number"),
            icon: Icons.block_rounded,
            onTap: () => Navigator.pop(context, 'block'),
          ),
          AuroraSettingTile(
            title: tr("Archive conversation"),
            icon: Icons.archive_outlined,
            onTap: () => Navigator.pop(context, 'archive'),
          ),
          AuroraSettingTile(
            title: tr("Open trash"),
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
        if (mounted) showAuroraSnack(context, tr("Number blocked"));
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
              Text(
                tr("Conversation details"),
                style: context.texts.headlineSmall,
              ),
              const SizedBox(height: 12),
              _detailRow(context, tr("Number"), widget.thread.address),
              _detailRow(context, tr("Name"), widget.thread.title),
              _detailRow(
                context,
                tr("Conversation ID"),
                '${widget.thread.threadId}',
              ),
              _detailRow(context, tr("Messages"), '${_messages.length}'),
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
    await SensitiveClipboard.copy(text);
    if (!mounted) return;
    setState(() => _selected.clear());
    showAuroraSnack(context, tr("Copied: {p0}", [count]));
  }

  Future<void> _bulkDelete() async {
    final count = _selected.length;
    final confirmed = await showAuroraDialog<bool>(
      context: context,
      title: Text(tr("Move messages to trash: {p0}?", [count])),
      content: Text(
        tr("You can restore these messages until the retention period ends."),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr("Cancel")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr("Move to trash")),
        ),
      ],
    );
    if (confirmed != true) return;
    try {
      await widget.repository.hideMessages(_selected.toList(growable: false));
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
      return;
    }
    if (!mounted) return;
    setState(() => _selected.clear());
    await _load(silent: true);
    widget.hub.refresh(silent: true);
  }

  Future<void> _openAttachment(Attachment attachment) async {
    if (_openingAttachment) return;
    _openingAttachment = true;
    ResizeImage? preview;
    try {
      final bytes = await widget.repository.attachmentData(attachment.uri);
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      final image = bytes == null
          ? null
          : ResizeImage(
              MemoryImage(bytes),
              width: 1600,
              height: 1600,
              policy: ResizeImagePolicy.fit,
            );
      preview = image;
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
                  child: image == null
                      ? AspectRatio(
                          aspectRatio: 4 / 3,
                          child: ColoredBox(
                            color: context.colors.surfaceContainerHigh,
                            child: Center(
                              child: Text(
                                attachment.name,
                                style: context.texts.bodyMedium,
                              ),
                            ),
                          ),
                        )
                      : InteractiveViewer(
                          child: Image(
                            image: image,
                            errorBuilder: (_, _, _) => Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                tr("Unable to decode image: {p0}", [
                                  attachment.name,
                                ]),
                              ),
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
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    } finally {
      _openingAttachment = false;
      await preview?.evict();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changeTimer?.cancel();
    _loadGeneration++;
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
    return PopScope(
      canPop: !selection,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selection) setState(() => _selected.clear());
      },
      child: AuroraScaffold(
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
                        title: widget.thread.title,
                        subtitle: widget.thread.isGroup
                            ? tr("Recipients: {p0}", [
                                widget.thread.recipients.length,
                              ])
                            : MessageFormat.phone(widget.thread.address),
                        actions: [
                          AuroraIconButton(
                            icon: Icons.more_horiz_rounded,
                            tooltip: tr("Conversation actions"),
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
                      Center(
                        child: AuroraEmpty(
                          title: tr("Start with a hello"),
                          message: tr("No messages in this conversation yet."),
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
                                onPressed: _paging
                                    ? null
                                    : () => _load(older: true),
                                child: Text(
                                  _paging
                                      ? tr("Loading\u2026")
                                      : tr("Load earlier messages"),
                                ),
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
                          return ReadReceiptObserver(
                            key: ValueKey('message-${message.id}'),
                            enabled:
                                AppScope.of(context).recycleReadCodes &&
                                _selected.isEmpty &&
                                _unreadCodeIds.contains(message.id),
                            onRead: () async {
                              try {
                                await widget.repository.hide(message.id);
                                _unreadCodeIds.remove(message.id);
                                if (mounted) await _load(silent: true);
                                widget.hub.refresh(silent: true);
                              } catch (error) {
                                if (mounted) {
                                  setState(() => _error = messageError(error));
                                }
                              }
                            },
                            child: MessageBubble(
                              message: message,
                              sims: _sims,
                              groupedTop: entry.groupedTop,
                              groupedBottom: entry.groupedBottom,
                              selected: _selected.contains(message.id),
                              onTap: _selected.isEmpty
                                  ? null
                                  : () => setState(() {
                                      if (!_selected.add(message.id)) {
                                        _selected.remove(message.id);
                                      }
                                    }),
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
                              onOpenLink: (url) =>
                                  widget.repository.openUrl(url),
                              onOpenAttachment: _openAttachment,
                            ),
                          );
                        },
                      ),
                    if (_showJump && !_loading && _messages.isNotEmpty)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: AuroraIconButton(
                          icon: Icons.keyboard_double_arrow_down_rounded,
                          tooltip: tr("Jump to latest"),
                          onPressed: _jumpToLatest,
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
                        tooltip: tr("Remove attachment"),
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
    return sim == null ? tr("Choose SIM") : simCardLabel(sim);
  }

  Widget _selectionBar(BuildContext context) {
    return AuroraTopBar(
      key: const ValueKey('selection'),
      showBack: false,
      leading: AuroraIconButton(
        icon: Icons.close_rounded,
        onPressed: () => setState(() => _selected.clear()),
      ),
      title: tr("Selected: {p0}", [_selected.length]),
      subtitle: tr("Copy or move to trash"),
      actions: [
        AuroraIconButton(
          icon: Icons.copy_rounded,
          tooltip: tr("Copy"),
          onPressed: _selected.isEmpty ? null : _bulkCopy,
        ),
        const SizedBox(width: 4),
        AuroraIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: tr("Move to trash"),
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
      final groupedTop =
          sameDay &&
          previous.outgoing == message.outgoing &&
          previous.subscriptionId == message.subscriptionId &&
          previous.sender == message.sender &&
          message.date - previous.date < 4 * 60 * 1000;
      final groupedBottom =
          next != null &&
          _sameDay(next.date, message.date) &&
          next.outgoing == message.outgoing &&
          next.subscriptionId == message.subscriptionId &&
          next.sender == message.sender &&
          next.date - message.date < 4 * 60 * 1000;
      entries.add(
        _Entry.message(
          message,
          groupedTop: groupedTop,
          groupedBottom: groupedBottom,
        ),
      );
      previous = message;
    }
    return entries;
  }

  bool _sameDay(int a, int b) {
    final first = DateTime.fromMillisecondsSinceEpoch(a);
    final second = DateTime.fromMillisecondsSinceEpoch(b);
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}

class _Entry {
  const _Entry.day(this.day)
    : message = null,
      groupedTop = false,
      groupedBottom = false;
  const _Entry.message(
    this.message, {
    required this.groupedTop,
    required this.groupedBottom,
  }) : day = null;

  final int? day;
  final SmsMessage? message;
  final bool groupedTop;
  final bool groupedBottom;
}
