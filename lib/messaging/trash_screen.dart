import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import 'format.dart';
import 'message_repository.dart';
import 'models.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, required this.repository});

  final MessageRepository repository;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<TrashItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.repository.trash();
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

  Future<void> _restore(TrashItem item) async {
    try {
      await widget.repository.restore(item.id);
      await _load();
      if (mounted) showAuroraSnack(context, tr("Restored to the conversation"));
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    }
  }

  Future<void> _delete(TrashItem item) async {
    final confirmed = await showAuroraDialog<bool>(
      context: context,
      title: Text(tr("Delete permanently?")),
      content: Text(
        tr(
          "This message from {p0} will be removed from the system message store. This cannot be undone.",
          [item.address],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr("Cancel")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: context.colors.error),
          child: Text(tr("Delete permanently")),
        ),
      ],
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteForever(item.id);
      await _load();
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    }
  }

  Future<void> _setRetention(int days) async {
    if (!mounted) return;
    AppScope.of(context).setTrashDays(days);
    try {
      await widget.repository.setTrashRetention(days);
      await widget.repository.purgeTrash(days);
      await _load();
      if (mounted) {
        showAuroraSnack(
          context,
          days == 0
              ? tr("Messages will be kept indefinitely")
              : tr("Items older than {p0} days will be removed", [days]),
        );
      }
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context);
    return AuroraScaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: AuroraTopBar(
                title: tr("Trash"),
                subtitle: tr("{p0} \u00b7 {p1}", [
                  _items.length,
                  settings.trashRetentionDays == 0
                      ? tr('Forever')
                      : tr('Days: {p0}', [settings.trashRetentionDays]),
                ]),
                actions: [
                  AuroraIconButton(
                    icon: Icons.cleaning_services_outlined,
                    tooltip: tr("Remove expired items"),
                    onPressed: () async {
                      final removed = await widget.repository.purgeTrash(
                        settings.trashRetentionDays,
                      );
                      await _load();
                      if (context.mounted) {
                        showAuroraSnack(
                          context,
                          removed == 0
                              ? tr("No expired items")
                              : tr("Expired messages removed: {p0}", [removed]),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: AuroraFilterBar(
                selected: '${settings.trashRetentionDays}',
                onSelected: (value) => _setRetention(int.parse(value)),
                items: [
                  AuroraFilterItem('7', tr("7 days")),
                  AuroraFilterItem('30', tr("30 days")),
                  AuroraFilterItem('90', tr("90 days")),
                  AuroraFilterItem('0', tr("Forever")),
                ],
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: AuroraErrorBanner(message: _error!, onRetry: _load),
              ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: AuroraLoading()),
                ),
              ),
            if (!_loading && _items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(top: 20),
                  child: AuroraEmpty(
                    title: tr("Trash is empty"),
                    message: tr(
                      "Deleted messages can be restored during their retention period.",
                    ),
                    icon: Icons.delete_outline_rounded,
                  ),
                ),
              )
            else if (!_loading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                sliver: SliverList.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10),
                      child: AuroraGlass(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  AuroraShapeContainer(
                                    shape:
                                        AuroraShapes.avatars[index %
                                            AuroraShapes.avatars.length],
                                    size: 40,
                                    gradient: [
                                      context.colors.surfaceContainerHighest,
                                      context.colors.surfaceContainerHigh,
                                    ],
                                    child: Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 17,
                                      color: context.colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.address,
                                          style: context.texts.titleSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          tr("Deleted {p0}", [
                                            MessageFormat.dateTime(
                                              item.deletedAt,
                                            ),
                                          ]),
                                          style: context.texts.labelSmall
                                              ?.copyWith(
                                                color: context
                                                    .colors
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                item.body.isEmpty ? tr("(No text)") : item.body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: context.texts.bodySmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _restore(item),
                                    icon: const Icon(
                                      Icons.restore_rounded,
                                      size: 17,
                                    ),
                                    label: Text(tr("Restore")),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _delete(item),
                                    style: TextButton.styleFrom(
                                      foregroundColor: context.colors.error,
                                    ),
                                    icon: const Icon(
                                      Icons.delete_forever_outlined,
                                      size: 17,
                                    ),
                                    label: Text(tr("Delete permanently")),
                                  ),
                                  const Spacer(),
                                  if (item.kind == 1)
                                    Text(
                                      tr("MMS messages"),
                                      style: context.texts.labelSmall?.copyWith(
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ],
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
