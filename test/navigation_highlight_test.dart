import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/aurora/aurora_widgets.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/settings/navigation_appearance.dart';

import 'support/fixture_message_repository.dart';

void main() {
  setUpAll(AppStrings.initialize);
  setUp(() => AppStrings.language = 'en');

  for (final brightness in Brightness.values) {
    testWidgets('White rim is visible and optional in ${brightness.name}', (
      tester,
    ) async {
      final settings = AppSettings()..navigationBlur = 0;
      final boundaryKey = GlobalKey();
      var selected = -1;
      await tester.pumpWidget(
        AppScope(
          settings: settings,
          child: MaterialApp(
            theme: buildAuroraTheme(
              brightness: brightness,
              appearance: const AuroraAppearance(),
            ),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: AuroraNavBar(
                    index: 0,
                    onSelected: (index) => selected = index,
                    destinations: const [
                      AuroraNavDestination(
                        icon: Icons.forum_outlined,
                        selectedIcon: Icons.forum,
                        label: 'Messages',
                      ),
                      AuroraNavDestination(
                        icon: Icons.tune,
                        selectedIcon: Icons.tune,
                        label: 'Settings',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<int> rimBrightness() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final offset = (image.width + image.width ~/ 2) * 4;
          return data.getUint8(offset) +
              data.getUint8(offset + 1) +
              data.getUint8(offset + 2);
        } finally {
          image.dispose();
        }
      }

      final highlighted = (await tester.runAsync(rimBrightness))!;
      settings.setNavigationHighlight(false);
      await tester.pumpAndSettle();
      final plain = (await tester.runAsync(rimBrightness))!;
      expect(highlighted, greaterThan(plain + 3));
      await tester.tap(find.text('Settings'));
      expect(selected, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    });
  }

  testWidgets(
    'Appearance toggle persists and reset restores the live preview',
    (tester) async {
      final repository = FixtureMessageRepository();
      final settings = AppSettings(repository: repository);
      await tester.pumpWidget(
        AppScope(
          settings: settings,
          child: MaterialApp(
            theme: buildAuroraTheme(
              brightness: Brightness.light,
              appearance: const AuroraAppearance(),
            ),
            home: const Scaffold(
              body: SingleChildScrollView(child: NavigationAppearance()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('navigation-highlight-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(settings.navigationHighlight, isFalse);
      expect((await repository.settingsAll())['navigationHighlight'], 'false');
      final surface = find.byKey(const ValueKey('navigation-capsule-surface'));
      expect(tester.widget<CustomPaint>(surface).foregroundPainter, isNull);
      await tester.ensureVisible(find.text('Reset to defaults'));
      await tester.tap(find.text('Reset to defaults'));
      await tester.pumpAndSettle();
      expect(settings.navigationHighlight, isTrue);
      expect(tester.widget<CustomPaint>(surface).foregroundPainter, isNotNull);
      expect((await repository.settingsAll())['navigationHighlight'], 'true');
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
