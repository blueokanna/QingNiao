import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_engine.dart';
import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/message_hub.dart';
import '../messaging/message_repository.dart';
import '../messaging/models.dart';
import 'appearance_screen.dart';
import 'device_compatibility_screen.dart';
import 'blocked_screen.dart';
import 'sync_screen.dart';

/// 设置主页面。分组遵循「权限 → 外观 → 消息 → 隐私 → 同步 → 关于」，
/// 所有改动即时生效并持久化。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.repository, required this.hub});

  final MessageRepository repository;
  final MessageHub hub;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  EngineStats _stats = const EngineStats();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await widget.repository.stats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {}
  }

  Future<void> _requestAccess() async {
    setState(() => _busy = true);
    try {
      await widget.repository.requestAccess();
      await widget.hub.refresh();
      await _loadStats();
    } catch (error) {
      if (mounted) showAuroraSnack(context, messageError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSignature(AppSettings settings) async {
    final controller = TextEditingController(text: settings.signature);
    final result = await showAuroraDialog<String>(
      context: context,
      title: const Text('短信签名'),
      content: TextField(
        controller: controller,
        maxLines: 3,
        maxLength: 80,
        decoration: const InputDecoration(hintText: '例如：—— 来自青鸟'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
      ],
    );
    if (result != null) settings.setSignature(result.trim());
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context);
    final hub = widget.hub;
    final access = hub.access;
    final scheme = context.colors;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(
          child: Row(
            children: [
              const SizedBox(width: 20),
              AuroraShapeContainer(
                shape: AuroraShapes.fab,
                size: 40,
                gradient: [scheme.primary, scheme.tertiary],
                child: Icon(Icons.tune_rounded, size: 19, color: scheme.onPrimary),
              ),
              const SizedBox(width: 10),
              Text(
                '设置',
                style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraLargeHeader(
            eyebrow: 'PREFERENCES',
            title: '设置',
            description: '外观、通知与隐私都在本机掌控',
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: '短信与权限',
            children: [
              AuroraSettingTile(
                title: access.defaultApp ? '默认短信应用已就绪' : '设为默认短信应用',
                subtitle: access.defaultApp
                    ? '可以完整读取、接收和发送短信'
                    : '只有默认应用才能写入系统短信库',
                icon: access.defaultApp ? Icons.verified_rounded : Icons.sms_outlined,
                trailing: access.defaultApp
                    ? Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20)
                    : null,
                onTap: access.defaultApp ? null : (_busy ? null : _requestAccess),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '通知权限',
                subtitle: access.notifications ? '已允许新短信通知' : '未允许，可能收不到提醒',
                icon: Icons.notifications_active_outlined,
                onTap: () => widget.repository.openNotificationSettings(),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '联系人读取',
                subtitle: access.readContacts ? '已允许显示联系人名称' : '未允许，仅显示号码',
                icon: Icons.contacts_outlined,
                onTap: () => widget.repository.openAppSettings(),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '设备与权限诊断',
                subtitle: '短信角色、后台限制与厂商设置',
                icon: Icons.phonelink_setup_rounded,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => DeviceCompatibilityScreen(repository: widget.repository),
                )),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: '外观与动效',
            children: [
              AuroraSettingTile(
                title: '外观',
                subtitle: switch (settings.themePreference) {
                  AuroraThemePreference.system => '跟随系统',
                  AuroraThemePreference.light => '浅色',
                  AuroraThemePreference.dark => '深色',
                },
                icon: Icons.palette_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AppearanceScreen(),
                  ),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '动态取色',
                subtitle: settings.useDynamic ? '跟随壁纸的 Material You 色彩' : '使用青鸟品牌色',
                icon: Icons.colorize_outlined,
                trailing: Switch(
                  value: settings.useDynamic,
                  onChanged: (value) => settings.setDynamic(value),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '流体动效',
                subtitle: '极光引擎统一调度，可随时降低强度',
                icon: Icons.auto_awesome_outlined,
                trailing: _MotionChips(settings: settings),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '字体大小',
                subtitle: '${(settings.fontScale * 100).round()}% · 影响会话与气泡',
                icon: Icons.text_fields_rounded,
                onTap: () => _fontScaleSheet(context, settings),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: '消息与通知',
            children: [
              AuroraSettingTile(
                title: '送达报告',
                subtitle: '显示已发送 / 已送达状态',
                icon: Icons.done_all_rounded,
                trailing: Switch(
                  value: settings.deliveryReports,
                  onChanged: (value) => settings.setDelivery(value),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '新短信通知',
                subtitle: '支持通知栏直接回复',
                icon: Icons.notifications_outlined,
                trailing: Switch(
                  value: settings.notifications,
                  onChanged: (value) => settings.setNotifications(value),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '通知显示内容预览',
                subtitle: settings.showPreview ? '在锁屏与通知中显示正文' : '仅显示号码',
                icon: Icons.visibility_outlined,
                trailing: Switch(
                  value: settings.showPreview,
                  onChanged: (value) => settings.setPreview(value),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '短信签名',
                subtitle: settings.signature.isEmpty ? '未设置' : settings.signature,
                icon: Icons.draw_outlined,
                onTap: () => _editSignature(settings),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '定时发送前确认',
                subtitle: settings.sendDelay ? '发送前等待几秒可撤销' : '立即发送',
                icon: Icons.schedule_rounded,
                trailing: Switch(
                  value: settings.sendDelay,
                  onChanged: (value) => settings.setSendDelay(value),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: '隐私与数据',
            children: [
              AuroraSettingTile(
                title: '黑名单',
                subtitle: '屏蔽号码，拦截通知',
                icon: Icons.block_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BlockedScreen(repository: widget.repository),
                  ),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '回收站保留',
                subtitle: settings.trashRetentionDays == 0
                    ? '永久保留'
                    : '${settings.trashRetentionDays} 天后自动清理',
                icon: Icons.delete_outline_rounded,
                onTap: () => _retentionSheet(context, settings),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '导出本地备份',
                subtitle: '包含短信、草稿与设置，不含彩信附件',
                icon: Icons.file_upload_outlined,
                onTap: () async {
                  final ok = await widget.repository.exportBackup();
                  if (context.mounted) showAuroraSnack(context, ok ? '备份已导出' : '已取消导出');
                },
                showDivider: true,
              ),
              AuroraSettingTile(
                title: '从备份恢复',
                subtitle: '导入会合并到现有短信库',
                icon: Icons.file_download_outlined,
                onTap: () async {
                  final confirmed = await showAuroraDialog<bool>(
                    context: context,
                    title: const Text('从备份恢复？'),
                    content: const Text('导入的短信将写入系统短信库，并记录到当前会话中。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('选择文件'),
                      ),
                    ],
                  );
                  if (confirmed != true) return;
                  final ok = await widget.repository.importBackup();
                  if (context.mounted) {
                    showAuroraSnack(context, ok ? '恢复完成' : '已取消恢复');
                  }
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: '云同步 · 端到端加密',
            children: [
              AuroraSettingTile(
                title: '青鸟同步',
                subtitle: '仅传输加密信封；服务器看不到正文',
                icon: Icons.cloud_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SyncScreen(repository: widget.repository),
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: '关于',
            children: [
              AuroraSettingTile(
                title: '青鸟短信',
                subtitle: '版本 0.4.0 · Flutter + Rust + Kotlin',
                icon: Icons.info_outline_rounded,
                onTap: () => showAuroraSheet<void>(
                  context: context,
                  builder: (context) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('青鸟短信', style: context.texts.headlineSmall),
                        const SizedBox(height: 6),
                        Text(
                          '本地优先的短信与彩信客户端。短信解析、搜索与回收站状态都留在设备上。',
                          style: context.texts.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _statRow(context, '会话', '${_stats.threads}'),
                        _statRow(context, '消息', '${_stats.messages}'),
                        _statRow(context, '回收站', '${_stats.trash}'),
                        _statRow(context, '验证码', '${_stats.otpCount}'),
                        _statRow(
                          context,
                          '引擎帧耗时',
                          '${AuroraEngine.instance.averageFrameMs.toStringAsFixed(1)} ms · ${_stats.quality}',
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => showLicensePage(
                            context: context,
                            applicationName: '青鸟短信',
                            applicationVersion: '0.4.0',
                          ),
                          icon: const Icon(Icons.code_rounded, size: 18),
                          label: const Text('开源许可'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(30, 10, 30, 130),
            child: Text(
              '青鸟短信 · 本地优先 · 无广告与统计 SDK\nRust 引擎 / Material 3 Expressive / 极光流体界面',
              textAlign: TextAlign.center,
              style: context.texts.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: .7),
                height: 1.7,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

  Future<void> _fontScaleSheet(BuildContext context, AppSettings settings) async {
    var scale = settings.fontScale;
    await showAuroraSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('字体大小', style: context.texts.titleLarge),
              const SizedBox(height: 6),
              Text(
                '${(scale * 100).round()}%',
                style: context.texts.headlineMedium?.copyWith(color: context.colors.primary),
              ),
              Slider(
                value: scale,
                min: .85,
                max: 1.25,
                divisions: 8,
                onChanged: (value) {
                  setSheetState(() => scale = value);
                  settings.setFontScale(value);
                },
              ),
              Text(
                '消息气泡与列表会同步缩放，系统级字体大小仍会叠加。',
                style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _retentionSheet(BuildContext context, AppSettings settings) async {
    final value = await showAuroraSheet<int>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final days in const [7, 30, 90, 0])
            AuroraSettingTile(
              title: days == 0 ? '永久保留' : '$days 天',
              subtitle: days == 0 ? '不自动清理回收站' : '删除后 $days 天内可恢复',
              icon: Icons.timer_outlined,
              trailing: settings.trashRetentionDays == days
                  ? Icon(Icons.check_circle_rounded, color: context.colors.primary, size: 20)
                  : null,
              onTap: () => Navigator.pop(context, days),
            ),
        ],
      ),
    );
    if (value == null) return;
    settings.setTrashDays(value);
    try {
      await widget.repository.setTrashRetention(value);
    } catch (_) {}
  }
}

class _MotionChips extends StatelessWidget {
  const _MotionChips({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final labels = {
      AuroraMotionLevel.full: '全速',
      AuroraMotionLevel.balanced: '平衡',
      AuroraMotionLevel.reduced: '省电',
    };
    return PopupMenuButton<AuroraMotionLevel>(
      tooltip: '动效强度',
      onSelected: settings.setMotion,
      itemBuilder: (context) => [
        for (final entry in labels.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: AuroraGlass(
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(labels[settings.motionLevel]!, style: context.texts.labelSmall),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}
