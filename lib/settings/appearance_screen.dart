import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_engine.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/models.dart';
import '../messaging/message_widgets.dart';
import 'navigation_appearance.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context);
    final scheme = context.colors;
    return AuroraScaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: AuroraTopBar(
                title: tr("Appearance"),
                subtitle: tr("Changes apply immediately"),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  requestFocusOnTap: false,
                  initialSelection: settings.localeCode,
                  label: Text(tr('Language')),
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: 'system',
                      label: tr('System default'),
                    ),
                    for (final code in AppStrings.languageCodes)
                      DropdownMenuEntry(
                        value: code,
                        label: AppStrings.languageNames[code]!,
                      ),
                  ],
                  onSelected: (value) {
                    if (value != null) settings.setLocale(value);
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: AuroraGlass(
                  radius: 30,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr("Preview"),
                        style: context.texts.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: .8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PreviewBubble(
                        outgoing: false,
                        text: tr("Are we still meeting tonight?"),
                      ),
                      _PreviewBubble(
                        outgoing: true,
                        text: tr("Yes, see you there."),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AuroraSection(
                title: tr("Theme"),
                children: [
                  AuroraSettingTile(
                    title: tr("AMOLED black"),
                    subtitle: tr(
                      "Use dark mode with a black background and no background glow",
                    ),
                    icon: Icons.nightlight_outlined,
                    trailing: Switch(
                      value: settings.amoled,
                      onChanged: settings.setAmoled,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: DropdownMenu<String>(
                      expandedInsets: EdgeInsets.zero,
                      requestFocusOnTap: false,
                      initialSelection: settings.fontFamily,
                      label: Text(tr("Font")),
                      dropdownMenuEntries: [
                        DropdownMenuEntry(
                          value: 'system',
                          label: tr("System font"),
                        ),
                        DropdownMenuEntry(
                          value: 'harmony',
                          label: tr("HarmonyOS Sans"),
                        ),
                        DropdownMenuEntry(
                          value: 'google',
                          label: 'Google Sans',
                        ),
                      ],
                      onSelected: (value) {
                        if (value != null) settings.setFontFamily(value);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      tr(
                        "Includes HarmonyOS Sans and Google Sans. Other scripts use system font fallback.",
                      ),
                      style: context.texts.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: tr("Qingniao"),
                    ),
                    child: Text(tr("Font licenses")),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownMenu<String>(
                      expandedInsets: EdgeInsets.zero,
                      requestFocusOnTap: false,
                      initialSelection: settings.launcherIcon,
                      label: Text(tr("App icon")),
                      dropdownMenuEntries: [
                        DropdownMenuEntry(value: 'bird', label: tr("Bird")),
                        DropdownMenuEntry(value: 'leaf', label: tr("Leaf")),
                        DropdownMenuEntry(value: 'chat', label: tr("Personal")),
                      ],
                      onSelected: (value) async {
                        if (value == null) return;
                        try {
                          await settings.setLauncherIcon(value);
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr(
                                    "Unable to change the app icon. Try again.",
                                  ),
                                ),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: AuroraFilterBar(
                      selected: switch (settings.themePreference) {
                        AuroraThemePreference.system => 'system',
                        AuroraThemePreference.light => 'light',
                        AuroraThemePreference.dark => 'dark',
                      },
                      onSelected: (value) => settings.setTheme(switch (value) {
                        'light' => AuroraThemePreference.light,
                        'dark' => AuroraThemePreference.dark,
                        _ => AuroraThemePreference.system,
                      }),
                      items: [
                        AuroraFilterItem('system', tr("System default")),
                        AuroraFilterItem('light', tr("Light")),
                        AuroraFilterItem('dark', tr("Dark")),
                      ],
                    ),
                  ),
                  AuroraSettingTile(
                    title: tr("Wallpaper colors"),
                    subtitle: settings.systemSeed == null
                        ? tr("System accent colors are unavailable")
                        : settings.useDynamic
                        ? tr("Using wallpaper colors")
                        : tr("Using reference palette"),
                    icon: Icons.colorize_outlined,
                    trailing: Switch(
                      value: settings.useDynamic,
                      onChanged: settings.systemSeed == null
                          ? null
                          : settings.setDynamic,
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: AuroraSection(
                title: tr("Reference palette"),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns =
                            constraints.maxWidth >= 280 &&
                                MediaQuery.textScalerOf(context).scale(12) <= 16
                            ? 3
                            : 2;
                        final width =
                            (constraints.maxWidth - 12 * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final entry in AuroraPalettes.seeds.entries)
                              SizedBox(
                                width: width,
                                child: _SeedSwatch(
                                  name: entry.key,
                                  color: entry.value,
                                  selected:
                                      !settings.useDynamic &&
                                      settings.seed == entry.value,
                                  onTap: () {
                                    settings.setDynamic(false);
                                    settings.setSeed(entry.key);
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: AuroraSection(
                title: tr("Bubbles and shapes"),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: AuroraFilterBar(
                      selected: switch (settings.bubbleStyle) {
                        AuroraBubbleStyle.soft => 'soft',
                        AuroraBubbleStyle.capsule => 'capsule',
                        AuroraBubbleStyle.cookie => 'cookie',
                      },
                      onSelected: (value) => settings.setBubble(switch (value) {
                        'capsule' => AuroraBubbleStyle.capsule,
                        'cookie' => AuroraBubbleStyle.cookie,
                        _ => AuroraBubbleStyle.soft,
                      }),
                      items: [
                        AuroraFilterItem('soft', tr("Soft")),
                        AuroraFilterItem('capsule', tr("Capsule")),
                        AuroraFilterItem('cookie', tr("Cookie")),
                      ],
                    ),
                  ),
                  AuroraSettingTile(
                    title: tr("Shape transitions"),
                    subtitle: tr(
                      "Avatars and indicators change shape with their state",
                    ),
                    icon: Icons.auto_awesome_mosaic_outlined,
                    trailing: Switch(
                      value: settings.morphShapes,
                      onChanged: settings.setMorph,
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: AuroraSection(
                title: tr("Motion and typography"),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: AuroraFilterBar(
                      selected: switch (settings.motionLevel) {
                        AuroraMotionLevel.full => 'full',
                        AuroraMotionLevel.balanced => 'balanced',
                        AuroraMotionLevel.reduced => 'reduced',
                      },
                      onSelected: (value) => settings.setMotion(switch (value) {
                        'balanced' => AuroraMotionLevel.balanced,
                        'reduced' => AuroraMotionLevel.reduced,
                        _ => AuroraMotionLevel.full,
                      }),
                      items: [
                        AuroraFilterItem('full', tr("Full")),
                        AuroraFilterItem('balanced', tr("Balanced")),
                        AuroraFilterItem('reduced', tr("Reduced")),
                      ],
                    ),
                  ),
                  AuroraSettingTile(
                    title: tr("Text size"),
                    subtitle: '${(settings.fontScale * 100).round()}%',
                    icon: Icons.text_fields_rounded,
                    trailing: SizedBox(
                      width: 150,
                      child: Slider(
                        value: settings.fontScale,
                        min: .85,
                        max: 1.25,
                        divisions: 8,
                        onChanged: settings.setFontScale,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: NavigationAppearance()),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({required this.outgoing, required this.text});

  final bool outgoing;
  final String text;

  @override
  Widget build(BuildContext context) {
    return MessageBubble(
      message: SmsMessage(
        id: outgoing ? 2 : 1,
        threadId: 1,
        address: 'demo',
        body: text,
        date: DateTime.now().millisecondsSinceEpoch,
        type: outgoing ? 2 : 1,
        read: true,
        status: 0,
      ),
      groupedTop: outgoing,
      groupedBottom: !outgoing,
    );
  }
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      label: name,
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          color: color.computeLuminance() > .179
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(12) * 2.6,
                  child: Center(
                    child: Text(
                      name.replaceFirst('PANTONE ', ''),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: context.texts.labelSmall?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
