import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import 'format.dart';
import 'message_repository.dart';
import 'models.dart';

/// 可恢复回收站。保留时长由用户设置，永久删除前二次确认。
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
      if (mounted) showAuroraSnack(context, '已恢复到原会话');
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    }
  }

  Future<void> _delete(TrashItem item) async {
    final confirmed = await showAuroraDialog<bool>(
      context: context,
      title: const Text('永久删除？'),
      content: Text('这条来自 ${item.address} 的消息将从系统短信库中移除，无法恢复。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: context.colors.error),
          child: const Text('永久删除'),
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
        showAuroraSnack(context, days == 0 ? '已设置为永久保留' : '超过 $days 天的项目会自动清理');
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
                title: '回收站',
                subtitle:
                    '${_items.length} 条 · ${settings.trashRetentionDays == 0 ? '永久保留' : '保留 ${settings.trashRetentionDays} 天'}',
                actions: [
                  AuroraIconButton(
                    icon: Icons.cleaning_services_outlined,
                    tooltip: '清理过期项目',
                    onPressed: () async {
                      final removed = await widget.repository.purgeTrash(
                        settings.trashRetentionDays,
                      );
                      await _load();
                      if (context.mounted) {
                        showAuroraSnack(
                          context,
                          removed == 0 ? '没有需要清理的项目' : '已清理 $removed 条过期消息',
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
                items: const [
                  AuroraFilterItem('7', '7 天'),
                  AuroraFilterItem('30', '30 天'),
                  AuroraFilterItem('90', '90 天'),
                  AuroraFilterItem('0', '永久'),
                ],
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
              ),
            if (!_loading && _items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: AuroraEmpty(
                    title: '回收站是空的',
                    message: '删除的短信会先来到这里，保留期内随时可以恢复。',
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
                      padding: const EdgeInsets.only(bottom: 10),
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
                                        AuroraShapes
                                            .avatars[index % AuroraShapes.avatars.length],
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
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.address,
                                          style: context.texts.titleSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '删除于 ${MessageFormat.dateTime(item.deletedAt)}',
                                          style: context.texts.labelSmall?.copyWith(
                                            color: context.colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                item.body.isEmpty ? '（无正文）' : item.body,
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
                                    icon: const Icon(Icons.restore_rounded, size: 17),
                                    label: const Text('恢复'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _delete(item),
                                    style: TextButton.styleFrom(
                                      foregroundColor: context.colors.error,
                                    ),
                                    icon: const Icon(Icons.delete_forever_outlined, size: 17),
                                    label: const Text('永久删除'),
                                  ),
                                  const Spacer(),
                                  if (item.kind == 1)
                                    Text(
                                      '彩信',
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
