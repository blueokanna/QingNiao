import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:qingniao/design/android_palette.dart';
import 'package:qingniao/aurora/aurora_backdrop.dart';

void main() {
  test('Dynamic color retains hue and tone at eighty percent chroma', () {
    for (final hue in [25.0, 130.0, 250.0, 310.0]) {
      final original = Hct.from(hue, 40, 60);
      final result = Hct.fromInt(
        softenDynamicColor(Color(original.toInt())).toARGB32(),
      );
      expect(result.hue, closeTo(original.hue, 1));
      expect(result.tone, closeTo(original.tone, .3));
      expect(result.chroma, closeTo(original.chroma * .8, 1));
    }
  });

  test(
    'System families retain distinct surface levels and readable foregrounds',
    () {
      const tones = [100, 99, 95, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0];
      final palette = AndroidPalette.fromMap({
        for (final name in [
          'accent1',
          'accent2',
          'accent3',
          'neutral1',
          'neutral2',
        ])
          name: tones
              .map(
                (t) => Hct.from(
                  name == 'accent3' ? 280 : 150,
                  name.startsWith('neutral') ? 6 : 40,
                  t.toDouble(),
                ).toInt(),
              )
              .toList(),
      })!;
      for (final brightness in Brightness.values) {
        final scheme = palette.applyTo(
          ColorScheme.fromSeed(seedColor: Colors.red, brightness: brightness),
        );
        expect(
          {
            scheme.surfaceContainerLowest,
            scheme.surfaceContainerLow,
            scheme.surfaceContainer,
            scheme.surfaceContainerHigh,
            scheme.surfaceContainerHighest,
          }.length,
          5,
        );
        for (final pair in [
          (scheme.primary, scheme.onPrimary),
          (scheme.surface, scheme.onSurface),
        ]) {
          final a = pair.$1.computeLuminance(), b = pair.$2.computeLuminance();
          final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
          expect(ratio, greaterThanOrEqualTo(4.5));
        }
      }
    },
  );

  test('AMOLED keeps a black canvas with visible static stars', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    AuroraStarPainter(
      surface: Colors.black,
      accent: Colors.teal,
      star: Colors.white,
      amoled: true,
    ).paint(canvas, const Size(200, 400));
    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 400);
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    var lit = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i] > 0 || bytes[i + 1] > 0 || bytes[i + 2] > 0) lit++;
    }
    expect(lit, greaterThan(0));
    expect(lit, lessThan(200 * 400 * .03));
    image.dispose();
    picture.dispose();
  });
}
