import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import '../aurora/aurora_theme.dart';
import '../aurora/aurora_widgets.dart';
import '../l10n/app_strings.dart';

/// Preview changes stay local while dragging; persistence happens on release.
class NavigationAppearance extends StatefulWidget {
  const NavigationAppearance({super.key});

  @override
  State<NavigationAppearance> createState() => _NavigationAppearanceState();
}

class _NavigationAppearanceState extends State<NavigationAppearance> {
  double? _blur;
  double? _opacity;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context);
    final blur = _blur ?? settings.navigationBlur;
    final opacity = _opacity ?? settings.navigationOpacity;
    final scheme = context.colors;
    return AuroraSection(
      title: tr('Navigation appearance'),
      children: [
        SizedBox(
          height: 144,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.mark_chat_unread_rounded,
                              color: scheme.onPrimaryContainer,
                              size: 36,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('Qingniao'),
                                    style: context.texts.titleMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    tr('Changes apply immediately'),
                                    style: context.texts.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AuroraNavBar(
                    index: 0,
                    blurSigma: blur,
                    surfaceOpacity: opacity,
                    onSelected: (_) {},
                    destinations: [
                      AuroraNavDestination(
                        icon: Icons.forum_outlined,
                        selectedIcon: Icons.forum,
                        label: tr('Messages'),
                      ),
                      AuroraNavDestination(
                        icon: Icons.shield_outlined,
                        selectedIcon: Icons.shield,
                        label: tr('Verification codes'),
                      ),
                      AuroraNavDestination(
                        icon: Icons.tune,
                        selectedIcon: Icons.tune,
                        label: tr('Settings'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${tr('Blur strength')} · ${blur.round()}'),
              Slider(
                value: blur,
                min: 0,
                max: 32,
                divisions: 32,
                label: '${blur.round()}',
                onChanged: (value) => setState(() => _blur = value),
                onChangeEnd: settings.setNavigationBlur,
              ),
              Text('${tr('Surface opacity')} · ${(opacity * 100).round()}%'),
              Slider(
                value: opacity,
                min: .55,
                max: .95,
                divisions: 40,
                label: '${(opacity * 100).round()}%',
                onChanged: (value) => setState(() => _opacity = value),
                onChangeEnd: settings.setNavigationOpacity,
              ),
              Text(
                tr('Preview updates while dragging. Zero turns blur off.'),
                style: context.texts.bodySmall,
              ),
              TextButton(
                onPressed: () {
                  settings.setNavigationBlur(18);
                  settings.setNavigationOpacity(.78);
                  setState(() {
                    _blur = null;
                    _opacity = null;
                  });
                },
                child: Text(tr('Reset to defaults')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
