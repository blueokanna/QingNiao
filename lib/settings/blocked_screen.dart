import 'package:qingniao/l10n/app_strings.dart';
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
      title:  Text(tr("Block a number")),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.phone,
        decoration:  InputDecoration(hintText: tr("Enter a number or short code")),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child:  Text(tr("Cancel"))),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child:  Text(tr("Block")),
        ),
      ],
    );
    final trimmed = number?.trim() ?? '';
    if (trimmed.isEmpty) return;
    try {
      await widget.repository.block(trimmed);
      await _load();
      if (mounted) showAuroraSnack(context, tr("Blocked: {p0}", [trimmed]));
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
                title: tr("Blocked numbers"),
                subtitle: tr("Numbers: {p0}", [_items.length]),
                actions: [
                  AuroraIconButton(
                    icon: Icons.add_rounded,
                    tooltip: tr("Add number"),
                    onPressed: _add,
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
                child: Text(
                  tr("Blocked messages remain in the system store, without notifications or inclusion in the regular inbox."),
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
               SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: AuroraEmpty(
                    title: tr("No blocked numbers"),
                    message: tr("Add numbers you do not want to hear from."),
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
                                ? tr("Blocked {p0}", [MessageFormat.inboxTime(item.createdAt)])
                                : item.note,
                          ),
                          trailing: TextButton(
                            onPressed: () => _remove(item),
                            child:  Text(tr("Unblock")),
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
