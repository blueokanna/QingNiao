import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/aurora/aurora_engine.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/design/android_palette.dart';

void main() {
  for (final damping in [.78, 1.0, 1.4]) {
    test('spring trajectory is frame independent at damping $damping', () {
      final slow = AuroraSpring(dampingRatio: damping)..animateTo(1);
      final fast = AuroraSpring(dampingRatio: damping)..animateTo(1);
      for (var frame = 0; frame < 6; frame++) {
        slow.drive(1 / 30);
      }
      for (var frame = 0; frame < 24; frame++) {
        fast.drive(1 / 120);
      }
      expect(slow.value, closeTo(fast.value, 1e-10));
      final before = slow.value;
      slow.animateTo(-1);
      expect(slow.value, before);
      slow.drive(10);
      expect(slow.value, -1);
      expect(slow.settled, isTrue);
      slow.dispose();
      fast.dispose();
    });
  }

  test('invalid spring parameters never enter the animation scheduler', () {
    expect(() => AuroraSpring(stiffness: 0), throwsArgumentError);
    expect(() => AuroraSpring(dampingRatio: double.nan), throwsArgumentError);
    expect(() => AuroraSpring(value: double.infinity), throwsArgumentError);
    final spring = AuroraSpring();
    expect(() => spring.animateTo(double.nan), throwsArgumentError);
    expect(() => spring.drive(-1), throwsArgumentError);
    spring.dispose();
  });

  testWidgets('idle and reduced motion stop ticking; interaction wakes it', (
    tester,
  ) async {
    final engine = AuroraEngine.instance;
    engine.configure(
      motion: AuroraMotionLevel.full,
      reduce: false,
      backdrop: false,
    );
    engine.resume();
    engine.attach(tester);
    final spring = engine.spring();
    addTearDown(() {
      engine.releaseSpring(spring);
      engine.detach();
    });
    expect(tester.binding.transientCallbackCount, 0);
    spring.animateTo(1);
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pump();
    for (var frame = 0; frame < 180; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(spring.value, 1);
    expect(tester.binding.transientCallbackCount, 0);
    engine.configure(motion: AuroraMotionLevel.reduced, reduce: false);
    spring.animateTo(2);
    expect(spring.value, 2);
    expect(engine.reduceMotion, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    engine.configure(motion: AuroraMotionLevel.full, reduce: false);
  });

  test('Monet rejects malformed data and accepts signed Android ARGB colors before chroma adjustment', () {
    expect(
      AndroidPalette.fromMap({
        'accent1': [0],
      }),
      isNull,
    );
    final palette = AndroidPalette.fromMap({
      for (final family in [
        'accent1',
        'accent2',
        'accent3',
        'neutral1',
        'neutral2',
      ])
        family: List.generate(13, (index) => -16777216 + index),
    })!;
    final light = palette.applyTo(ColorScheme.fromSeed(seedColor: Colors.blue));
    final dark = palette.applyTo(
      ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
    );
    expect(light.primary, softenDynamicColor(const Color(0xff000008)));
    expect(dark.primary, softenDynamicColor(const Color(0xff000004)));
    expect(dark.onPrimary, softenDynamicColor(const Color(0xff00000a)));
  });

  test('AMOLED is black and bundled fonts retain Chinese fallback', () {
    final theme = buildAuroraTheme(
      brightness: Brightness.dark,
      appearance: const AuroraAppearance(amoled: true, fontFamily: 'google'),
    );
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.surface, Colors.black);
    expect(theme.colorScheme.surfaceContainerLowest, Colors.black);
    expect(theme.textTheme.bodyLarge!.fontFamily, 'GoogleSans');
    expect(
      theme.textTheme.bodyLarge!.fontFamilyFallback,
      contains('HarmonyOSSans'),
    );
  });
}
