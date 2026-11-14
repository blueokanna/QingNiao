import 'package:flutter/material.dart';

import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/format.dart';
import '../messaging/message_repository.dart';
import '../messaging/models.dart';

class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key, required this.repository});

  final MessageRepository repository;

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  List<BlockedNumber> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.blocked();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = messageError(error);
      });
    }
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final number = await showAuroraDialog<String>(
      context: context,
      title: const Text('屏蔽号码'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(hintText: '输入号码或短号'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('屏蔽'),
        ),
      ],
    );
    final trimmed = number?.trim() ?? '';
    if (trimmed.isEmpty) return;
    try {
      await widget.repository.block(trimmed);
      await _load();
      if (mounted) showAuroraSnack(context, '已屏蔽 $trimmed');
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    }
  }

  Future<void> _remove(BlockedNumber item) async {
    try {
      await widget.repository.unblock(item.address);
      await _load();
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuroraScaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: AuroraTopBar(
                title: '黑名单',
                subtitle: '${_items.length} 个号码',
                actions: [
                  AuroraIconButton(
                    icon: Icons.add_rounded,
                    tooltip: '添加号码',
                    onPressed: _add,
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
                child: Text(
                  '被屏蔽号码的短信仍会保存在系统中，但不会触发通知，也不会出现在普通筛选里。',
                  style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(child: AuroraErrorBanner(message: _error!, onRetry: _load)),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: AuroraLoading()),
                ),
              )
            else if (_items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: AuroraEmpty(
                    title: '黑名单是空的',
                    message: '把不想再被打扰的号码放进来。',
                    icon: Icons.block_rounded,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                sliver: SliverList.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AuroraGlass(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: context.colors.errorContainer,
                            child: Icon(
                              Icons.block_rounded,
                              color: context.colors.onErrorContainer,
                              size: 20,
                            ),
                          ),
                          title: Text(MessageFormat.phone(item.address)),
                          subtitle: Text(
                            item.note.isEmpty
                                ? '屏蔽于 ${MessageFormat.inboxTime(item.createdAt)}'
                                : item.note,
                          ),
                          trailing: TextButton(
                            onPressed: () => _remove(item),
                            child: const Text('解除'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
