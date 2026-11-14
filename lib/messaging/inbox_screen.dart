import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../aurora/aurora_engine.dart';
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
import 'trash_screen.dart';

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
      if (mounted) showAuroraSnack(context, messageError(error), icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  // ignore: unused_element
  Future<void> _compose() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComposeScreen(repository: widget.repository, hub: widget.hub),
      ),
    );
    await widget.hub.refresh(silent: true);
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
        (thread) => thread.address == address || thread.recipients.contains(address),
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
    } catch (_) {
      // 冷启动权限未就绪时忽略；用户仍可从列表进入。
    }
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
                AuroraAvatar(seed: thread.address, size: 42, label: thread.title),
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
            title: thread.pinned ? '取消置顶' : '置顶会话',
            icon: thread.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            onTap: () => Navigator.pop(context, 'pin'),
          ),
          AuroraSettingTile(
            title: thread.archived ? '移出存档' : '归档会话',
            icon: Icons.archive_outlined,
            onTap: () => Navigator.pop(context, 'archive'),
          ),
          AuroraSettingTile(
            title: '标为已读',
            icon: Icons.mark_chat_read_outlined,
            onTap: () => Navigator.pop(context, 'read'),
          ),
          AuroraSettingTile(
            title: '屏蔽此号码',
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
        if (mounted) showAuroraSnack(context, '已屏蔽 ${thread.title}');
    }
  }

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
        final pinned = hub.threads.where((thread) => thread.pinned).toList(growable: false);
        final recent = hub.threads.where((thread) => !thread.pinned).toList(growable: false);
        return RefreshIndicator(
          onRefresh: () => hub.refresh(),
          color: context.colors.primary,
          backgroundColor: context.colors.surfaceContainerHigh,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: _brandBar(context, hub)),
              SliverToBoxAdapter(
                child: AuroraLargeHeader(
                  eyebrow: MessageFormat.todayLabel(),
                  title: '消息',
                  description: hub.access.ready
                      ? '${hub.unread} 条未读 · ${hub.threads.length} 个会话'
                      : '本地优先的短信与彩信',
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 2),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: AuroraSearchField(
                    controller: _search,
                    hintText: '搜索号码、联系人或是短信里的短语',
                    onChanged: hub.search,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: AuroraFilterBar(
                  selected: hub.filter,
                  onSelected: hub.setFilter,
                  items: [
                    AuroraFilterItem('all', '全部', count: hub.countFor('all')),
                    AuroraFilterItem('unread', '未读', count: hub.countFor('unread')),
                    AuroraFilterItem('otp', '验证码', count: hub.countFor('otp')),
                    AuroraFilterItem('pinned', '置顶', count: hub.countFor('pinned')),
                    AuroraFilterItem('archived', '存档', count: hub.countFor('archived')),
                  ],
                ),
              ),
              if (!hub.access.ready) SliverToBoxAdapter(child: _accessCard(context, hub)),
              if (hub.error != null)
                SliverToBoxAdapter(
                  child: AuroraErrorBanner(message: hub.error!, onRetry: () => hub.refresh()),
                ),
              if (hub.loading && hub.threads.isEmpty)
                const SliverToBoxAdapter(child: _InboxSkeleton()),
              if (!hub.loading && hub.access.ready && hub.threads.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: AuroraEmpty(
                      title: hub.query.isNotEmpty ? '没有找到匹配的消息' : '收件箱很安静',
                      message: hub.query.isNotEmpty
                          ? '换个关键词，或清空搜索看看全部会话。'
                          : '新的短信会像光一样落在这里。',
                      icon: Icons.mark_chat_unread_outlined,
                      action: hub.query.isNotEmpty
                          ? TextButton(
                              onPressed: () {
                                _search.clear();
                                hub.search('');
                              },
                              child: const Text('清空搜索'),
                            )
                          : null,
                    ),
                  ),
                ),
              if (pinned.isNotEmpty) ...[
                SliverToBoxAdapter(child: _sectionLabel(context, '置顶')),
                _threadSliver(pinned),
              ],
              if (recent.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _sectionLabel(context, pinned.isEmpty ? '全部会话' : '最近'),
                ),
                _threadSliver(recent),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
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
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Dismissible(
              key: ValueKey('thread-${thread.threadId}'),
              direction: DismissDirection.horizontal,
              background: _SwipeBackground(
                alignment: Alignment.centerLeft,
                color: context.colors.primary,
                icon: thread.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                label: thread.pinned ? '取消置顶' : '置顶',
              ),
              secondaryBackground: _SwipeBackground(
                alignment: Alignment.centerRight,
                color: context.colors.tertiary,
                icon: Icons.archive_outlined,
                label: '归档',
              ),
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  await widget.hub.pin(thread.threadId, !thread.pinned);
                } else {
                  await widget.hub.archive(thread.threadId, true);
                }
                return false;
              },
              child: ConversationTile(
                thread: thread,
                showSim: widget.hub.sims.length > 1,
                onTap: () => _openThread(thread),
                onLongPress: () => _actions(thread),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _brandBar(BuildContext context, MessageHub hub) {
    final scheme = context.colors;
    return Padding(
      // 沉浸式状态下为系统状态栏让位；列表其余部分可以继续从其下方流过。
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 8, 16, 0),
      child: Row(
        children: [
          AuroraShapeContainer(
            shape: AuroraShapes.bloom,
            size: 40,
            gradient: [scheme.primary, scheme.tertiary],
            border: scheme.onPrimary.withValues(alpha: .2),
            child: Icon(Icons.bolt_rounded, size: 19, color: scheme.onPrimary),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '青鸟短信',
                style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '短信与彩信',
                style: context.texts.labelSmall?.copyWith(
                  fontSize: 8.5,
                  letterSpacing: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Spacer(),
          AuroraIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: '回收站',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrashScreen(repository: widget.repository),
                ),
              );
              widget.hub.refresh(silent: true);
            },
          ),
          const SizedBox(width: 8),
          AuroraIconButton(
            icon: Icons.bolt_outlined,
            tooltip: '引擎状态',
            onPressed: () => _showEngine(context, hub),
          ),
        ],
      ),
    );
  }

  void _showEngine(BuildContext context, MessageHub hub) {
    final engine = AuroraEngine.instance;
    showAuroraSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('极光引擎', style: context.texts.headlineSmall),
            const SizedBox(height: 6),
            Text(
              '统一帧调度 · 自适应画质 · 跨页连续动效',
              style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            AuroraGlass(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _engineRow(context, '渲染质量', engine.quality.name),
                  _engineRow(context, '平均帧耗时', '${engine.averageFrameMs.toStringAsFixed(1)} ms'),
                  _engineRow(context, '背景帧率', '${engine.backdropFps} fps'),
                  _engineRow(context, '会话数量', '${hub.threads.length}'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '引擎根据真实 build/raster 耗时自动降级；滚动时背景让出 GPU 预算。',
              style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _engineRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const Spacer(),
          Text(value, style: context.texts.titleSmall),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 8),
      child: Text(
        label,
        style: context.texts.labelMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
          letterSpacing: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _accessCard(BuildContext context, MessageHub hub) {
    final scheme = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: AuroraGlass(
        padding: const EdgeInsets.all(20),
        gradient: [
          Color.alphaBlend(scheme.primaryContainer.withValues(alpha: .5), scheme.surface),
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
                  child: Icon(Icons.sms_outlined, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('把青鸟设为默认短信应用', style: context.texts.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                        '只有默认短信应用才能完整读取、接收与发送短信。',
                        style: context.texts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
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
                  label: Text(_requesting ? '等待系统确认…' : '去设置'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => widget.repository.openAppSettings(),
                  child: const Text('应用设置'),
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

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final left = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      padding: EdgeInsets.only(left: left ? 24 : 0, right: left ? 0 : 24),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: .18),
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!left) Text(label, style: context.texts.labelSmall?.copyWith(color: color)),
          if (!left) const SizedBox(width: 8),
          Icon(icon, color: color, size: 20),
          if (left) const SizedBox(width: 8),
          if (left) Text(label, style: context.texts.labelSmall?.copyWith(color: color)),
        ],
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
              padding: const EdgeInsets.only(bottom: 8),
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
                          color: context.colors.onSurface.withValues(alpha: .05),
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
                                color: context.colors.onSurface.withValues(alpha: .06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: context.colors.onSurface.withValues(alpha: .04),
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
