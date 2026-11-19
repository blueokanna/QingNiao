import 'network_push_screen.dart';

import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_engine.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/message_hub.dart';
import '../messaging/message_repository.dart';
import '../messaging/models.dart';
import 'appearance_screen.dart';
import 'device_compatibility_screen.dart';
import 'blocked_screen.dart';
import 'sync_screen.dart';
import '../updates/update_controller.dart';
import '../updates/update_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.hub,
  });

  final MessageRepository repository;
  final MessageHub hub;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  EngineStats _stats = const EngineStats();
  Map<String, dynamic> _capabilities = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    try {
      final caps = await widget.repository.notificationCapabilities();
      if (mounted) setState(() => _capabilities = caps);
    } catch (_) {}
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

  Future<void> _swipeSheet(AppSettings settings, bool left) async {
    final action = await showAuroraSheet<ThreadSwipeAction>(
      context: context,
      builder: (context) => RadioGroup<ThreadSwipeAction>(
        groupValue: left ? settings.swipeLeft : settings.swipeRight,
        onChanged: (value) => Navigator.pop(context, value),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in ThreadSwipeAction.values)
              RadioListTile<ThreadSwipeAction>(
                value: action,
                title: Text(swipeActionLabel(action)),
              ),
          ],
        ),
      ),
    );
    if (action != null) settings.setSwipe(left: left, action: action);
  }

  Future<void> _editSignature(AppSettings settings) async {
    final controller = TextEditingController(text: settings.signature);
    final result = await showAuroraDialog<String>(
      context: context,
      title: Text(tr("Message signature")),
      content: TextField(
        controller: controller,
        maxLines: 3,
        maxLength: 80,
        decoration: InputDecoration(
          hintText: tr("Example: Sent from Qingniao"),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr("Cancel")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(tr("Save")),
        ),
      ],
    );
    if (result != null) settings.setSignature(result.trim());
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context);
    final updates = UpdateScope.maybeOf(context);
    final hub = widget.hub;
    final access = hub.access;
    final scheme = context.colors;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).top + 8),
        ),
        SliverToBoxAdapter(
          child: AuroraLargeHeader(
            title: tr("Settings"),
            description: tr("Appearance, notifications and privacy"),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: tr("SMS permissions"),
            children: [
              AuroraSettingTile(
                title: access.ready
                    ? tr("Default SMS app is ready")
                    : access.defaultApp
                    ? tr('SMS access needs attention')
                    : tr("Set as default SMS app"),
                subtitle: access.ready
                    ? tr("SMS reading, receiving and sending are available")
                    : access.defaultApp
                    ? tr(
                        'Grant SMS permissions to receive and display messages',
                      )
                    : tr(
                        "Only the default SMS app can write to the system message store",
                      ),
                icon: access.ready
                    ? Icons.verified_rounded
                    : Icons.sms_outlined,
                trailing: access.ready
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: scheme.primary,
                        size: 20,
                      )
                    : null,
                onTap: access.ready ? null : (_busy ? null : _requestAccess),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Notification permission"),
                subtitle: access.notifications
                    ? tr("New message notifications are allowed")
                    : tr("Notifications are not allowed"),
                icon: Icons.notifications_active_outlined,
                onTap: () => widget.repository.openNotificationSettings(),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr('SIM information'),
                subtitle: access.readPhoneState
                    ? tr('SIM names and eSIM details are available')
                    : tr(
                        'Allow phone access to identify the SIM for each message',
                      ),
                icon: Icons.sim_card_outlined,
                onTap: () => widget.repository.openAppSettings(),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Contact permission"),
                subtitle: access.readContacts
                    ? tr("Contact names can be displayed")
                    : tr("Only phone numbers are displayed"),
                icon: Icons.contacts_outlined,
                onTap: () => widget.repository.openAppSettings(),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Device diagnostics"),
                subtitle: tr(
                  "SMS role, background restrictions and device settings",
                ),
                icon: Icons.phonelink_setup_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeviceCompatibilityScreen(
                      repository: widget.repository,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: tr("Appearance and motion"),
            children: [
              AuroraSettingTile(
                title: tr("Appearance"),
                subtitle: switch (settings.themePreference) {
                  AuroraThemePreference.system => tr("System default"),
                  AuroraThemePreference.light => tr("Light"),
                  AuroraThemePreference.dark => tr("Dark"),
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
                title: tr("Dynamic colors"),
                subtitle: settings.useDynamic
                    ? tr("Use wallpaper colors")
                    : tr("Use reference palette colors"),
                icon: Icons.colorize_outlined,
                trailing: Switch(
                  value: settings.useDynamic,
                  onChanged: (value) => settings.setDynamic(value),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Interface motion"),
                subtitle: tr("Choose how much animation to use"),
                icon: Icons.auto_awesome_outlined,
                trailing: _MotionChips(settings: settings),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Text size"),
                subtitle: tr(
                  "{p0}% \u00b7 Applies to messages and conversations",
                  [(settings.fontScale * 100).round()],
                ),
                icon: Icons.text_fields_rounded,
                onTap: () => _fontScaleSheet(context, settings),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: tr('Swipe actions'),
            children: [
              for (final left in [true, false])
                AuroraSettingTile(
                  title: left ? tr('Swipe left') : tr('Swipe right'),
                  subtitle: swipeActionLabel(
                    left ? settings.swipeLeft : settings.swipeRight,
                  ),
                  icon: left
                      ? Icons.swipe_left_rounded
                      : Icons.swipe_right_rounded,
                  onTap: () => _swipeSheet(settings, left),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: tr("Messages and notifications"),
            children: [
              AuroraSettingTile(
                title: tr("Delivery reports"),
                subtitle: tr("Show sent and delivered states"),
                icon: Icons.done_all_rounded,
                trailing: Switch(
                  value: settings.deliveryReports,
                  onChanged: (value) => settings.setDelivery(value),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr('Network push'),
                icon: Icons.cloud_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        NetworkPushScreen(repository: widget.repository),
                  ),
                ),
              ),
              AuroraSettingTile(
                title: tr("Recycle codes after reading"),
                subtitle: tr(
                  "Unread codes move to trash after two seconds fully visible in a conversation",
                ),
                icon: Icons.auto_delete_outlined,
                trailing: Switch(
                  value: settings.recycleReadCodes,
                  onChanged: settings.setRecycleReadCodes,
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("New message notifications"),
                subtitle: tr("Reply directly from notifications"),
                icon: Icons.notifications_outlined,
                trailing: Switch(
                  value: settings.notifications,
                  onChanged: (value) => settings.setNotifications(value),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Show message previews"),
                subtitle: settings.showPreview
                    ? tr(
                        "Show message text on the lock screen and in notifications",
                      )
                    : tr("Show numbers only"),
                icon: Icons.visibility_outlined,
                trailing: Switch(
                  value: settings.showPreview,
                  onChanged: (value) => settings.setPreview(value),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Live updates"),
                subtitle: _capabilities['fluidCloud'] == true
                    ? (settings.fluidCloud
                          ? tr(
                              'Enabled · Supported systems may show unread message live updates',
                            )
                          : tr('Disabled · Use standard notifications'))
                    : tr(
                        'Android 16 Live Updates are unavailable on this device',
                      ),
                icon: Icons.bubble_chart_outlined,
                trailing: Switch(
                  value:
                      settings.fluidCloud &&
                      _capabilities['fluidCloud'] == true,
                  onChanged: _capabilities['fluidCloud'] == true
                      ? settings.setFluidCloud
                      : null,
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Background activity and startup"),
                subtitle: _capabilities['batteryUnrestricted'] == true
                    ? tr(
                        "Battery optimization is excluded. Check startup permissions too.",
                      )
                    : tr(
                        "SMS uses system broadcasts. Background restrictions may delay notifications.",
                      ),
                icon: Icons.battery_charging_full_rounded,
                onTap: () => _backgroundSheet(settings),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Message signature"),
                subtitle: settings.signature.isEmpty
                    ? tr("Not set")
                    : settings.signature,
                icon: Icons.draw_outlined,
                onTap: () => _editSignature(settings),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Confirm scheduled messages"),
                subtitle: settings.sendDelay
                    ? tr("Wait briefly before sending to allow cancellation")
                    : tr("Send immediately"),
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
            title: tr("Privacy and data"),
            children: [
              AuroraSettingTile(
                title: tr("Blocked numbers"),
                subtitle: tr("Block numbers and their notifications"),
                icon: Icons.block_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        BlockedScreen(repository: widget.repository),
                  ),
                ),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Trash retention"),
                subtitle: settings.trashRetentionDays == 0
                    ? tr("Keep indefinitely")
                    : tr("Remove after {p0} days", [
                        settings.trashRetentionDays,
                      ]),
                icon: Icons.delete_outline_rounded,
                onTap: () => _retentionSheet(context, settings),
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr('Export backup'),
                subtitle: tr(
                  'Includes SMS, drafts, pinned and archived conversations and blocked numbers, without MMS attachments',
                ),
                icon: Icons.file_upload_outlined,
                onTap: () async {
                  final ok = await widget.repository.exportBackup();
                  if (context.mounted) {
                    showAuroraSnack(
                      context,
                      ok ? tr("Backup exported") : tr("Export canceled"),
                    );
                  }
                },
                showDivider: true,
              ),
              AuroraSettingTile(
                title: tr("Restore backup"),
                subtitle: tr(
                  "Imported messages are merged into the system store",
                ),
                icon: Icons.file_download_outlined,
                onTap: () async {
                  final confirmed = await showAuroraDialog<bool>(
                    context: context,
                    title: Text(tr('Restore from backup?')),
                    content: Text(
                      tr(
                        'Imported messages, drafts, conversation states and blocked numbers are merged with existing records.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr("Cancel")),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(tr("Choose file")),
                      ),
                    ],
                  );
                  if (confirmed != true) return;
                  final ok = await widget.repository.importBackup();
                  if (context.mounted) {
                    showAuroraSnack(
                      context,
                      ok ? tr("Restore complete") : tr("Restore canceled"),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AuroraSection(
            title: tr("Encrypted sync"),
            children: [
              AuroraSettingTile(
                title: tr("Device sync"),
                subtitle: tr(
                  "Transfer encrypted envelopes through your server",
                ),
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
            title: tr("About"),
            children: [
              if (updates != null)
                AuroraSettingTile(
                  title: tr('App updates'),
                  subtitle: updates.release == null
                      ? tr('Check for updates')
                      : tr('Update available: {p0}', [
                          updates.release!.versionName,
                        ]),
                  icon: Icons.system_update_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UpdateScreen(controller: updates),
                    ),
                  ),
                  showDivider: true,
                ),
              AuroraSettingTile(
                title: tr("Qingniao"),
                subtitle: tr('Version {p0}', [
                  updates?.versionName.isNotEmpty == true
                      ? updates!.versionName
                      : '—',
                ]),
                icon: Icons.info_outline_rounded,
                onTap: () => showAuroraSheet<void>(
                  context: context,
                  builder: (context) => Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr("Qingniao"),
                          style: context.texts.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(
                            "A local-first SMS and MMS client. Message analysis, search and local state stay on your device.",
                          ),
                          style: context.texts.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _statRow(
                          context,
                          tr("Conversations"),
                          '${_stats.threads}',
                        ),
                        _statRow(context, tr("Messages"), '${_stats.messages}'),
                        _statRow(context, tr("Trash"), '${_stats.trash}'),
                        _statRow(
                          context,
                          tr("Verification codes"),
                          '${_stats.otpCount}',
                        ),
                        _statRow(
                          context,
                          tr("Frame time"),
                          '${AuroraEngine.instance.averageFrameMs.toStringAsFixed(1)} ms · ${_stats.quality}',
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () => showLicensePage(
                            context: context,
                            applicationName: tr("Qingniao"),
                            applicationVersion: updates?.versionName,
                          ),
                          icon: const Icon(Icons.code_rounded, size: 18),
                          label: Text(tr("Open-source licenses")),
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
              tr(
                "Qingniao \u00b7 Local-first messaging\nFlutter, Rust and Kotlin",
              ),
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

  Future<void> _backgroundSheet(AppSettings settings) async {
    await showAuroraSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr("Receiving messages in the background"),
              style: context.texts.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${tr("Android Telephony broadcasts deliver incoming messages directly to this app.")} ${tr("Delivery does not depend on a push server. Device background restrictions can still affect notifications.")}',
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            AuroraSettingTile(
              title: tr("Battery optimization exemption"),
              subtitle: _capabilities['batteryUnrestricted'] == true
                  ? tr("Allowed")
                  : tr("Reduce restrictions while the screen is off"),
              icon: Icons.battery_saver_outlined,
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await widget.repository.requestBatteryUnrestricted();
                await _loadCapabilities();
                if (mounted) {
                  showAuroraSnack(
                    context,
                    ok
                        ? tr("Battery settings opened")
                        : tr("Allow background activity in system settings"),
                  );
                }
              },
            ),
            AuroraSettingTile(
              title: tr("OPPO / OnePlus startup settings"),
              subtitle: tr("Open device startup or background settings"),
              icon: Icons.settings_applications_outlined,
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await widget.repository.openAutoStartSettings();
                if (mounted && !ok) {
                  showAuroraSnack(
                    context,
                    tr(
                      "Startup settings are unavailable. Use App info instead.",
                    ),
                  );
                }
              },
            ),
            AuroraSettingTile(
              title: tr("Notification and banner permissions"),
              subtitle: tr("Allow new message notification banners"),
              icon: Icons.notifications_active_outlined,
              onTap: () {
                Navigator.pop(sheetContext);
                widget.repository.openNotificationSettings();
              },
            ),
            AuroraSettingTile(
              title: tr("Live update indicator"),
              subtitle: _capabilities['fluidCloud'] == true
                  ? tr('This device supports Android 16 Live Updates')
                  : tr(
                      'Requires supported Android 16 software. The system may still decline promotion.',
                    ),
              icon: Icons.bubble_chart_outlined,
              trailing: Switch(
                value:
                    settings.fluidCloud && _capabilities['fluidCloud'] == true,
                onChanged: _capabilities['fluidCloud'] == true
                    ? settings.setFluidCloud
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(value, style: context.texts.titleSmall),
        ],
      ),
    );
  }

  Future<void> _fontScaleSheet(
    BuildContext context,
    AppSettings settings,
  ) async {
    var scale = settings.fontScale;
    await showAuroraSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr("Text size"), style: context.texts.titleLarge),
              const SizedBox(height: 6),
              Text(
                '${(scale * 100).round()}%',
                style: context.texts.headlineMedium?.copyWith(
                  color: context.colors.primary,
                ),
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
                tr(
                  "Text scales with both this setting and the system accessibility setting.",
                ),
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _retentionSheet(
    BuildContext context,
    AppSettings settings,
  ) async {
    final value = await showAuroraSheet<int>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final days in const [7, 30, 90, 0])
            AuroraSettingTile(
              title: days == 0
                  ? tr("Keep indefinitely")
                  : tr("Days: {p0}", [days]),
              subtitle: days == 0
                  ? tr("Do not automatically empty trash")
                  : tr("Restore messages within {p0} days of deletion", [days]),
              icon: Icons.timer_outlined,
              trailing: settings.trashRetentionDays == days
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: context.colors.primary,
                      size: 20,
                    )
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
      AuroraMotionLevel.full: tr("Full"),
      AuroraMotionLevel.balanced: tr("Balanced"),
      AuroraMotionLevel.reduced: tr("Reduced"),
    };
    return MenuAnchor(
      menuChildren: [
        for (final entry in labels.entries)
          MenuItemButton(
            onPressed: () => settings.setMotion(entry.key),
            child: Text(entry.value),
          ),
      ],
      builder: (context, controller, child) => TextButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.expand_more_rounded),
        label: Text(labels[settings.motionLevel]!),
      ),
      child: AuroraGlass(
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labels[settings.motionLevel]!,
              style: context.texts.labelSmall,
            ),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}
