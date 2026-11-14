import '../messaging/sensitive_clipboard.dart';

import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import 'trash_screen.dart';

import 'package:material_new_shapes/material_new_shapes.dart';

import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/format.dart';
import '../messaging/message_hub.dart';
import '../messaging/message_repository.dart';
import '../messaging/message_widgets.dart';
import '../messaging/models.dart';
import 'compose_screen.dart';
import 'conversation_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.repository, required this.hub});

  final MessageRepository repository;
  final MessageHub hub;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _requesting = false;
  bool _bulkBusy = false;
  bool _selecting = false;
  final Set<int> _selected = {};
  int _handledIntent = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIntent());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.hub.refresh(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _requestAccess() async {
    setState(() => _requesting = true);
    try {
      await widget.repository.requestAccess();
      await widget.hub.refresh();
    } catch (error) {
      if (mounted) {
        showAuroraSnack(
          context,
          messageError(error),
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _openThread(ThreadSummary thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          repository: widget.repository,
          hub: widget.hub,
          thread: thread,
        ),
      ),
    );
    await widget.hub.refresh(silent: true);
  }

  Future<void> _openIntent() async {
    try {
      final data = await widget.repository.launchIntent();
      final address = '${data['address'] ?? ''}'.trim();
      if (address.isEmpty || !mounted) return;
      await widget.hub.refresh(silent: true);
      if (!mounted || !widget.hub.access.ready) return;
      final matches = widget.hub.threads.where(
        (thread) =>
            thread.address == address || thread.recipients.contains(address),
      );
      if (matches.isNotEmpty) {
        await _openThread(matches.first);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ComposeScreen(
              repository: widget.repository,
              hub: widget.hub,
              initialRecipient: address,
            ),
          ),
        );
        await widget.hub.refresh(silent: true);
      }
    } catch (_) {}
  }

  Future<void> _actions(ThreadSummary thread) async {
    final action = await showAuroraSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Row(
              children: [
                AuroraAvatar(
                  seed: thread.address,
                  size: 42,
                  label: thread.title,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(thread.title, style: context.texts.titleMedium),
                      Text(
                        MessageFormat.phone(thread.address),
                        style: context.texts.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AuroraSettingTile(
            title: thread.pinned ? tr("Unpin") : tr("Pin conversation"),
            icon: thread.pinned
                ? Icons.push_pin_outlined
                : Icons.push_pin_rounded,
            onTap: () => Navigator.pop(context, 'pin'),
          ),
          AuroraSettingTile(
            title: thread.archived
                ? tr("Unarchive")
                : tr("Archive conversation"),
            icon: Icons.archive_outlined,
            onTap: () => Navigator.pop(context, 'archive'),
          ),
          AuroraSettingTile(
            title: tr("Mark as read"),
            icon: Icons.mark_chat_read_outlined,
            onTap: () => Navigator.pop(context, 'read'),
          ),
          AuroraSettingTile(
            title: tr("Block this number"),
            icon: Icons.block_rounded,
            destructive: true,
            onTap: () => Navigator.pop(context, 'block'),
          ),
        ],
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'pin':
        await widget.hub.pin(thread.threadId, !thread.pinned);
      case 'archive':
        await widget.hub.archive(thread.threadId, !thread.archived);
      case 'read':
        await widget.hub.markRead(thread.threadId);
      case 'block':
        await widget.hub.block(thread.address);
        if (mounted) {
          showAuroraSnack(context, tr("Blocked: {p0}", [thread.title]));
        }
    }
  }

  void _toggle(ThreadSummary thread) => setState(() {
    _selecting = true;
    if (!_selected.add(thread.threadId)) _selected.remove(thread.threadId);
  });

  Future<void> _perform(Future<void> Function() operation) async {
    if (_bulkBusy) return;
    setState(() => _bulkBusy = true);
    try {
      await operation();
      await widget.hub.refresh(silent: true);
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _bulk(String action) async {
    final ids = _selected.toList(growable: false);
    if (ids.isEmpty) return;
    if (action == 'trash') {
      final confirmed = await showAuroraDialog<bool>(
        context: context,
        title: Text(tr('Move conversations to trash: {p0}?', [ids.length])),
        content: Text(
          tr('You can restore these messages until the retention period ends.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Move to trash')),
          ),
        ],
      );
      if (confirmed != true || !mounted) return;
    }
    await _perform(() async {
      switch (action) {
        case 'trash':
          await widget.repository.trashThreads(ids);
        case 'read':
          await widget.repository.markThreadsRead(ids);
        case 'copy':
          final text = await widget.repository.copyThreads(ids);
          await SensitiveClipboard.copy(text);
          if (mounted) showAuroraSnack(context, tr('Copied'));
      }
      if (mounted) {
        setState(() {
          _selected.clear();
          _selecting = false;
        });
      }
    });
  }

  Future<void> _swipe(ThreadSummary thread, ThreadSwipeAction action) =>
      _perform(() async {
        switch (action) {
          case ThreadSwipeAction.trash:
            await widget.repository.trashThreads([thread.threadId]);
            if (mounted) showAuroraSnack(context, tr('Moved to trash'));
          case ThreadSwipeAction.read:
            await widget.repository.markRead(thread.threadId);
          case ThreadSwipeAction.archive:
            await widget.repository.archive(thread.threadId, !thread.archived);
          case ThreadSwipeAction.pin:
            await widget.repository.pin(thread.threadId, !thread.pinned);
          case ThreadSwipeAction.none:
            break;
        }
      });

  Widget _toolbar() => SliverAppBar(
    primary: false,
    pinned: true,
    automaticallyImplyLeading: false,
    backgroundColor: context.colors.surface,
    surfaceTintColor: Colors.transparent,
    titleTextStyle: context.texts.titleLarge,
    title: Text(
      _selecting ? tr('Selected: {p0}', [_selected.length]) : tr('Messages'),
    ),
    leading: _selecting
        ? IconButton(
            tooltip: tr('Cancel'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() {
              _selecting = false;
              _selected.clear();
            }),
          )
        : null,
    actions: _selecting
        ? [
            IconButton(
              tooltip: tr('Select all'),
              icon: const Icon(Icons.select_all_rounded),
              onPressed: _bulkBusy
                  ? null
                  : () => setState(
                      () => _selected.addAll(
                        widget.hub.threads.map((t) => t.threadId),
                      ),
                    ),
            ),
            MenuAnchor(
              menuChildren: [
                for (final action in ['copy', 'read', 'trash'])
                  MenuItemButton(
                    onPressed: _bulkBusy || _selected.isEmpty
                        ? null
                        : () => _bulk(action),
                    child: Text(
                      action == 'copy'
                          ? tr('Copy text')
                          : action == 'read'
                          ? tr('Mark as read')
                          : tr('Move to trash'),
                    ),
                  ),
                if (_selected.length == 1)
                  MenuItemButton(
                    onPressed: () => _actions(
                      widget.hub.threads.firstWhere(
                        (t) => _selected.contains(t.threadId),
                      ),
                    ),
                    child: Text(tr('View details')),
                  ),
              ],
              builder: (context, controller, child) => IconButton(
                tooltip: tr('Actions'),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ),
          ]
        : [
            IconButton(
              tooltip: tr('Mark all as read'),
              icon: const Icon(Icons.done_all_rounded),
              onPressed: _bulkBusy || !widget.hub.access.ready
                  ? null
                  : () => _perform(widget.repository.markAllRead),
            ),
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  onPressed: () => setState(() => _selecting = true),
                  child: Text(tr('Select conversations')),
                ),
                MenuItemButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TrashScreen(repository: widget.repository),
                    ),
                  ),
                  child: Text(tr('Trash')),
                ),
              ],
              builder: (context, controller, child) => IconButton(
                tooltip: tr('Actions'),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ),
          ],
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.hub,
      builder: (context, _) {
        final hub = widget.hub;
        if (hub.intentTick != _handledIntent) {
          _handledIntent = hub.intentTick;
          WidgetsBinding.instance.addPostFrameCallback((_) => _openIntent());
        }
        final pinned = hub.threads
            .where((thread) => thread.pinned)
            .toList(growable: false);
        final recent = hub.threads
            .where((thread) => !thread.pinned)
            .toList(growable: false);
        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _selecting) {
              setState(() {
                _selecting = false;
                _selected.clear();
              });
            }
          },
          child: RefreshIndicator(
            onRefresh: () => hub.refresh(),
            color: context.colors.primary,
            backgroundColor: context.colors.surfaceContainerHigh,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.paddingOf(context).top + 8,
                  ),
                ),
                _toolbar(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                    child: AuroraSearchField(
                      controller: _search,
                      hintText: tr("Search messages or contacts"),
                      onChanged: hub.search,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: AuroraFilterBar(
                    selected: hub.filter,
                    onSelected: hub.setFilter,
                    items: [
                      AuroraFilterItem(
                        'all',
                        tr("All"),
                        count: hub.countFor('all'),
                      ),
                      AuroraFilterItem(
                        'unread',
                        tr("Unread"),
                        count: hub.countFor('unread'),
                      ),
                      AuroraFilterItem(
                        'otp',
                        tr("Verification codes"),
                        count: hub.countFor('otp'),
                      ),
                      AuroraFilterItem(
                        'pinned',
                        tr("Pinned"),
                        count: hub.countFor('pinned'),
                      ),
                      AuroraFilterItem(
                        'archived',
                        tr("Archived"),
                        count: hub.countFor('archived'),
                      ),
                    ],
                  ),
                ),
                if (!hub.access.ready && !hub.loading)
                  SliverToBoxAdapter(child: _accessCard(context, hub)),
                if (hub.error != null)
                  SliverToBoxAdapter(
                    child: AuroraErrorBanner(
                      message: hub.error!,
                      onRetry: () => hub.refresh(),
                    ),
                  ),
                if (hub.loading && hub.threads.isEmpty)
                  const SliverToBoxAdapter(child: _InboxSkeleton()),
                if (!hub.loading && hub.access.ready && hub.threads.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(top: 30),
                      child: AuroraEmpty(
                        title: hub.query.isNotEmpty
                            ? tr("No matching messages")
                            : tr("Your inbox is empty"),
                        message: hub.query.isNotEmpty
                            ? tr("Try another keyword or clear your search.")
                            : tr("New messages will appear here."),
                        icon: Icons.mark_chat_unread_outlined,
                        action: hub.query.isNotEmpty
                            ? TextButton(
                                onPressed: () {
                                  _search.clear();
                                  hub.search('');
                                },
                                child: Text(tr("Clear search")),
                              )
                            : null,
                      ),
                    ),
                  ),
                if (pinned.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _sectionLabel(context, tr("Pinned")),
                  ),
                  _threadSliver(pinned),
                ],
                if (recent.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _sectionLabel(
                      context,
                      pinned.isEmpty ? tr("All conversations") : tr("Recent"),
                    ),
                  ),
                  _threadSliver(recent),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _threadSliver(List<ThreadSummary> threads) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: threads.length,
        itemBuilder: (context, index) {
          final thread = threads[index];
          final settings = AppScope.maybeOf(context);
          final left = settings?.swipeLeft ?? ThreadSwipeAction.trash;
          final right = settings?.swipeRight ?? ThreadSwipeAction.read;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final start = rtl ? left : right;
          final end = rtl ? right : left;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Dismissible(
                key: ValueKey('thread-${thread.threadId}'),
                direction: _selecting || _bulkBusy
                    ? DismissDirection.none
                    : start == ThreadSwipeAction.none &&
                          end == ThreadSwipeAction.none
                    ? DismissDirection.none
                    : start == ThreadSwipeAction.none
                    ? DismissDirection.endToStart
                    : end == ThreadSwipeAction.none
                    ? DismissDirection.startToEnd
                    : DismissDirection.horizontal,
                resizeDuration: null,
                dismissThresholds: const {
                  DismissDirection.startToEnd: .38,
                  DismissDirection.endToStart: .38,
                },
                background: _swipeBackground(
                  start,
                  AlignmentDirectional.centerStart,
                ),
                secondaryBackground: _swipeBackground(
                  end,
                  AlignmentDirectional.centerEnd,
                ),
                confirmDismiss: (direction) async {
                  await _swipe(
                    thread,
                    direction == DismissDirection.startToEnd ? start : end,
                  );
                  return false;
                },
                child: ConversationTile(
                  thread: thread,
                  selected: _selected.contains(thread.threadId),
                  selectionMode: _selecting,
                  showSim: widget.hub.sims.length > 1,
                  onTap: () =>
                      _selecting ? _toggle(thread) : _openThread(thread),
                  onLongPress: () => _toggle(thread),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _swipeBackground(
    ThreadSwipeAction action,
    AlignmentGeometry alignment,
  ) => _SwipeBackground(
    alignment: alignment,
    color: action == ThreadSwipeAction.trash
        ? context.colors.error
        : context.colors.primary,
    icon: switch (action) {
      ThreadSwipeAction.trash => Icons.delete_outline_rounded,
      ThreadSwipeAction.read => Icons.done_all_rounded,
      ThreadSwipeAction.archive => Icons.archive_outlined,
      ThreadSwipeAction.pin => Icons.push_pin_outlined,
      ThreadSwipeAction.none => Icons.block_rounded,
    },
    label: swipeActionLabel(action),
  );

  Widget _sectionLabel(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
    child: Text(label, style: context.texts.labelLarge),
  );

  Widget _accessCard(BuildContext context, MessageHub hub) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: AuroraGlass(
        padding: const EdgeInsets.all(20),
        gradient: [
          Color.alphaBlend(
            scheme.primaryContainer.withValues(alpha: .5),
            scheme.surface,
          ),
          scheme.surfaceContainerLow.withValues(alpha: .4),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AuroraShapeContainer(
                  shape: MaterialShapes.arch,
                  size: 44,
                  color: scheme.primaryContainer,
                  child: Icon(
                    Icons.sms_outlined,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr("Make Qingniao your default SMS app"),
                        style: context.texts.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tr(
                          "The default SMS role is required to read, receive and send messages.",
                        ),
                        style: context.texts.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  onPressed: _requesting ? null : _requestAccess,
                  icon: _requesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined, size: 18),
                  label: Text(
                    _requesting
                        ? tr("Waiting for system confirmation\u2026")
                        : tr("Set as default SMS app"),
                  ),
                ),
                TextButton(
                  onPressed: () => widget.repository.openAppSettings(),
                  child: Text(tr("App settings")),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final AlignmentGeometry alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final left = alignment == AlignmentDirectional.centerStart;
    return Container(
      alignment: alignment,
      padding: EdgeInsetsDirectional.only(
        start: left ? 24 : 0,
        end: left ? 0 : 24,
      ),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: .18),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(26),
        ),
      ),
      child: Tooltip(
        message: label,
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          for (var index = 0; index < 4; index++)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8),
              child: AuroraGlass(
                height: 82,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.colors.onSurface.withValues(
                            alpha: .05,
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 120,
                              height: 12,
                              decoration: BoxDecoration(
                                color: context.colors.onSurface.withValues(
                                  alpha: .06,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: context.colors.onSurface.withValues(
                                  alpha: .04,
                                ),
                                borderRadius: BorderRadius.circular(8),
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
        ],
      ),
    );
  }
}
