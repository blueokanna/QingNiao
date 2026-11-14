import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/aurora/aurora_widgets.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Capsule blurs a changing backdrop in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final swapped = ValueNotifier(false);
      addTearDown(swapped.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAuroraTheme(
            brightness: brightness,
            appearance: const AuroraAppearance(),
          ),
          home: RepaintBoundary(
            key: boundaryKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: swapped,
                  builder: (context, reverse, _) => Row(
                    children: [
                      Expanded(
                        child: ColoredBox(
                          color: reverse ? Colors.white : Colors.black,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: reverse ? Colors.black : Colors.white,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AuroraNavBar(
                    index: 0,
                    onSelected: (_) {},
                    destinations: const [
                      AuroraNavDestination(
                        icon: Icons.forum_outlined,
                        selectedIcon: Icons.forum,
                        label: 'Messages',
                      ),
                      AuroraNavDestination(
                        icon: Icons.shield_outlined,
                        selectedIcon: Icons.shield,
                        label: 'Codes',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<List<int>> sample(int y) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          return [
            for (final x in [130, 166, 194, 230])
              bytes.getUint8((y * image.width + x) * 4),
          ];
        } finally {
          image.dispose();
        }
      }

      final before = (await tester.runAsync(() => sample(145)))!;
      // An actual Gaussian spreads the hard black/white seam into both sides.
      expect(before[1], greaterThan(before[0] + 2));
      expect(before[2], lessThan(before[3] - 2));
      expect(before[1], lessThan(before[2]));
      final outside = (await tester.runAsync(() => sample(40)))!;
      expect(outside, [0, 0, 255, 255]);

      // Repaint only the scene behind the bar; its widget is never rebuilt.
      swapped.value = true;
      await tester.pump();
      final after = (await tester.runAsync(() => sample(145)))!;
      expect(after[1], lessThan(after[0] - 2));
      expect(after[2], greaterThan(after[3] + 2));
      expect(after[1], greaterThan(after[2]));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
