import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Reduce perceived chroma while preserving hue and tone, not opacity.
Color softenDynamicColor(Color color) {
  final hct = Hct.fromInt(color.toARGB32());
  return Color(Hct.from(hct.hue, hct.chroma * .8, hct.tone).toInt());
}

class AndroidPalette {
  AndroidPalette._(this._tones);
  final Map<String, List<Color>> _tones;

  static AndroidPalette? fromMap(Map<dynamic, dynamic>? source) {
    if (source == null) return null;
    final tones = <String, List<Color>>{};
    for (final name in [
      'accent1',
      'accent2',
      'accent3',
      'neutral1',
      'neutral2',
    ]) {
      final values = source[name];
      if (values is! List ||
          values.length != 13 ||
          values.any((value) => value is! int)) {
        return null;
      }
      tones[name] = values
          .cast<int>()
          .map((value) => softenDynamicColor(Color(value & 0xffffffff)))
          .toList(growable: false);
    }
    return AndroidPalette._(tones);
  }

  ColorScheme applyTo(ColorScheme base) {
    final dark = base.brightness == Brightness.dark;
    final primary = _tones['accent1']!;
    final secondary = _tones['accent2']!;
    final tertiary = _tones['accent3']!;
    final neutral = _tones['neutral1']!;
    final variant = _tones['neutral2']!;
    Color tone(List<Color> family, double value) {
      final sample = Hct.fromInt(family[7].toARGB32());
      return Color(Hct.from(sample.hue, sample.chroma, value).toInt());
    }

    return base.copyWith(
      primary: primary[dark ? 4 : 8],
      onPrimary: primary[dark ? 10 : 0],
      primaryContainer: primary[dark ? 9 : 3],
      onPrimaryContainer: primary[dark ? 3 : 11],
      secondary: secondary[dark ? 4 : 8],
      onSecondary: secondary[dark ? 10 : 0],
      secondaryContainer: secondary[dark ? 9 : 3],
      onSecondaryContainer: secondary[dark ? 3 : 11],
      tertiary: tertiary[dark ? 4 : 8],
      onTertiary: tertiary[dark ? 10 : 0],
      tertiaryContainer: tertiary[dark ? 9 : 3],
      onTertiaryContainer: tertiary[dark ? 3 : 11],
      surface: tone(neutral, dark ? 6 : 98),
      onSurface: neutral[dark ? 3 : 11],
      onSurfaceVariant: variant[dark ? 4 : 9],
      outline: variant[dark ? 6 : 7],
      outlineVariant: variant[dark ? 9 : 4],
      surfaceContainerLowest: tone(neutral, dark ? 4 : 100),
      surfaceContainerLow: tone(neutral, dark ? 10 : 96),
      surfaceContainer: tone(neutral, dark ? 12 : 94),
      surfaceContainerHigh: tone(neutral, dark ? 17 : 92),
      surfaceContainerHighest: tone(neutral, dark ? 22 : 90),
      surfaceDim: tone(neutral, dark ? 6 : 87),
      surfaceBright: tone(neutral, dark ? 24 : 98),
      surfaceTint: primary[dark ? 4 : 8],
      primaryFixed: primary[3],
      primaryFixedDim: primary[4],
      onPrimaryFixed: primary[11],
      onPrimaryFixedVariant: primary[9],
      secondaryFixed: secondary[3],
      secondaryFixedDim: secondary[4],
      onSecondaryFixed: secondary[11],
      onSecondaryFixedVariant: secondary[9],
      tertiaryFixed: tertiary[3],
      tertiaryFixedDim: tertiary[4],
      onTertiaryFixed: tertiary[11],
      onTertiaryFixedVariant: tertiary[9],
      inverseSurface: neutral[dark ? 3 : 10],
      onInverseSurface: neutral[dark ? 10 : 2],
      inversePrimary: primary[dark ? 8 : 4],
    );
  }
}
