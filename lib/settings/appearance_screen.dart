import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_engine.dart';
import '../aurora/aurora_shapes.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../messaging/models.dart';
import '../messaging/message_widgets.dart';

/// 外观工作台：色板、气泡、动效与字号的实时预览。
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
                title: '外观',
                subtitle: '改动即时生效',
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
                        '实时预览',
                        style: context.texts.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: .8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PreviewBubble(outgoing: false, text: '今晚的极光，像一条慢慢展开的短信。'),
                      _PreviewBubble(outgoing: true, text: '那就把这条留在青鸟里。'),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AuroraSection(
                title: '主题',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: AuroraFilterBar(
                      selected: switch (settings.themePreference) {
                        AuroraThemePreference.system => 'system',
                        AuroraThemePreference.light => 'light',
                        AuroraThemePreference.dark => 'dark',
                      },
                      onSelected: (value) => settings.setTheme(
                        switch (value) {
                          'light' => AuroraThemePreference.light,
                          'dark' => AuroraThemePreference.dark,
                          _ => AuroraThemePreference.system,
                        },
                      ),
                      items: const [
                        AuroraFilterItem('system', '跟随系统'),
                        AuroraFilterItem('light', '浅色'),
                        AuroraFilterItem('dark', '深色'),
                      ],
                    ),
                  ),
                  AuroraSettingTile(
                    title: 'Material You 动态取色',
                    subtitle: settings.systemSeed == null
                        ? '当前设备未提供系统强调色'
                        : settings.useDynamic
                        ? '已跟随壁纸'
                        : '使用品牌色',
                    icon: Icons.colorize_outlined,
                    trailing: Switch(
                      value: settings.useDynamic,
                      onChanged: settings.systemSeed == null ? null : settings.setDynamic,
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: AuroraSection(
                title: '色板',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final entry in AuroraPalettes.seeds.entries)
                          _SeedSwatch(
                            name: entry.key,
                            color: entry.value,
                            selected: !settings.useDynamic && settings.seed == entry.value,
                            onTap: () {
                              settings.setDynamic(false);
                              settings.setSeed(entry.key);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: AuroraSection(
                title: '气泡与形状',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: AuroraFilterBar(
                      selected: switch (settings.bubbleStyle) {
                        AuroraBubbleStyle.soft => 'soft',
                        AuroraBubbleStyle.capsule => 'capsule',
                        AuroraBubbleStyle.cookie => 'cookie',
                      },
                      onSelected: (value) => settings.setBubble(
                        switch (value) {
                          'capsule' => AuroraBubbleStyle.capsule,
                          'cookie' => AuroraBubbleStyle.cookie,
                          _ => AuroraBubbleStyle.soft,
                        },
                      ),
                      items: const [
                        AuroraFilterItem('soft', '柔和'),
                        AuroraFilterItem('capsule', '胶囊'),
                        AuroraFilterItem('cookie', '饼干'),
                      ],
                    ),
                  ),
                  AuroraSettingTile(
                    title: '形状形变',
                    subtitle: '头像与指示器在状态变化时连续形变',
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
                title: '动效与排版',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: AuroraFilterBar(
                      selected: switch (settings.motionLevel) {
                        AuroraMotionLevel.full => 'full',
                        AuroraMotionLevel.balanced => 'balanced',
                        AuroraMotionLevel.reduced => 'reduced',
                      },
                      onSelected: (value) => settings.setMotion(
                        switch (value) {
                          'balanced' => AuroraMotionLevel.balanced,
                          'reduced' => AuroraMotionLevel.reduced,
                          _ => AuroraMotionLevel.full,
                        },
                      ),
                      items: const [
                        AuroraFilterItem('full', '全速'),
                        AuroraFilterItem('balanced', '平衡'),
                        AuroraFilterItem('reduced', '省电'),
                      ],
                    ),
                  ),
                  AuroraSettingTile(
                    title: '字体大小',
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
                  AuroraSettingTile(
                    title: '省电极光',
                    subtitle: '限制背景光团数量与帧率',
                    icon: Icons.battery_saver_outlined,
                    trailing: Switch(
                      value: settings.lowPowerAurora,
                      onChanged: (value) {
                        settings.setLowPower(value);
                        AuroraEngine.instance.configure(
                          motion: value ? AuroraMotionLevel.reduced : AuroraMotionLevel.full,
                          reduce: false,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
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
    return AuroraPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [color, Color.lerp(color, Colors.white, .3)!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: color.withValues(alpha: .4), blurRadius: 18)]
                  : null,
            ),
            child: selected
                ? Icon(Icons.check_rounded, color: Colors.white, size: 22)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: context.texts.labelSmall?.copyWith(
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

extension on Icons {
  static const colorize = Icons.colorize_outlined;
}

