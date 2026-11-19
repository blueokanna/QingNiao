import 'package:flutter/material.dart';

import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../l10n/app_strings.dart';
import 'update_controller.dart';

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final update = controller.release;
      final phase = controller.phase;
      final colors = context.colors;
      return Scaffold(
        appBar: AppBar(title: Text(tr('App updates'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    update == null
                        ? Icons.system_update_outlined
                        : Icons.download_for_offline_outlined,
                    size: 36,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(switch (phase) {
                    'checking' => tr('Checking for updates'),
                    'downloading' => tr('Downloading update'),
                    'verifying' => tr('Verifying update'),
                    'ready' => tr('Ready to install'),
                    'current' => tr('You are up to date'),
                    'no_release' => tr('No stable release is available'),
                    _ =>
                      update == null
                          ? tr('App updates')
                          : tr('Update available: {p0}', [update.versionName]),
                  }, style: context.texts.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    tr('Installed version: {p0} ({p1})', [
                      controller.versionName.isEmpty
                          ? '—'
                          : controller.versionName,
                      controller.versionCode,
                    ]),
                    style: context.texts.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (update != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${update.versionName} · ${(update.size / 1048576).toStringAsFixed(1)} MB',
                    ),
                  ],
                  if (controller.busy) ...[
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: phase == 'downloading'
                          ? controller.progress
                          : null,
                      borderRadius: BorderRadius.circular(4),
                      semanticsLabel: tr('Downloading update'),
                    ),
                    if (phase == 'downloading') ...[
                      const SizedBox(height: 8),
                      Text(
                        '${((controller.progress ?? 0) * 100).floor()}%',
                        style: context.texts.labelMedium,
                      ),
                    ],
                  ],
                  if (controller.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      switch (controller.error) {
                        'download_failed' => tr(
                          'Download or verification failed. Check your connection and retry.',
                        ),
                        'install_failed' => tr(
                          'Installation could not start. Check install permission and try again.',
                        ),
                        'settings_failed' => tr(
                          'Could not save update preferences. Try again.',
                        ),
                        _ => tr(
                          'Could not check for updates. Check your connection and try again.',
                        ),
                      },
                      style: context.texts.bodyMedium?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (update != null)
                        FilledButton.icon(
                          onPressed: controller.busy
                              ? null
                              : phase == 'ready'
                              ? controller.install
                              : controller.download,
                          icon: Icon(
                            phase == 'ready'
                                ? Icons.install_mobile_rounded
                                : Icons.download_rounded,
                          ),
                          label: Text(
                            phase == 'ready'
                                ? controller.canInstall
                                      ? tr('Install update')
                                      : tr('Allow app installation')
                                : tr('Download update'),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: controller.busy ? null : controller.check,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(tr('Check for updates')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(tr('Automatically check for updates')),
              subtitle: Text(
                tr(
                  'Check on launch and every {p0} minutes while the app is open.',
                  [UpdateController.checkInterval.inMinutes],
                ),
              ),
              value: controller.automatic,
              onChanged: controller.setAutomatic,
            ),
            if (controller.lastChecked != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  tr('Last checked: {p0}', [
                    MaterialLocalizations.of(context).formatTimeOfDay(
                      TimeOfDay.fromDateTime(controller.lastChecked!),
                      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                        context,
                      ),
                    ),
                  ]),
                  style: context.texts.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                tr(
                  'Updates come from GitHub Releases. Android asks for confirmation before installation.',
                ),
                style: context.texts.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            if (update != null) ...[
              const SizedBox(height: 12),
              if (update.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    update.notes,
                    style: context.texts.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await controller.repository.openUrl(update.pageUrl);
                  } catch (_) {
                    if (context.mounted) {
                      showAuroraSnack(
                        context,
                        tr('Could not open release notes'),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(tr('View release on GitHub')),
              ),
            ],
          ],
        ),
      );
    },
  );
}
