import 'package:flutter/material.dart';

class AndroidPalette {
  AndroidPalette._(this._tones);
  final Map<String, List<Color>> _tones;

  static AndroidPalette? fromMap(Map<dynamic, dynamic>? source) {
    if (source == null) return null;
    final tones = <String, List<Color>>{};
    for (final name in ['accent1', 'accent2', 'accent3', 'neutral1', 'neutral2']) {
      final values = source[name];
      if (values is! List || values.length != 13 || values.any((value) => value is! int)) return null;
      tones[name] = values.cast<int>().map((value) => Color(value & 0xffffffff)).toList(growable: false);
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
    return base.copyWith(
      primary: primary[dark ? 4 : 8], onPrimary: primary[dark ? 10 : 0],
      primaryContainer: primary[dark ? 9 : 3], onPrimaryContainer: primary[dark ? 3 : 11],
      secondary: secondary[dark ? 4 : 8], onSecondary: secondary[dark ? 10 : 0],
      secondaryContainer: secondary[dark ? 9 : 3], onSecondaryContainer: secondary[dark ? 3 : 11],
      tertiary: tertiary[dark ? 4 : 8], onTertiary: tertiary[dark ? 10 : 0],
      tertiaryContainer: tertiary[dark ? 9 : 3], onTertiaryContainer: tertiary[dark ? 3 : 11],
      surface: neutral[dark ? 11 : 1], onSurface: neutral[dark ? 3 : 11],
      onSurfaceVariant: variant[dark ? 4 : 9], outline: variant[dark ? 6 : 7],
      outlineVariant: variant[dark ? 9 : 4],
      surfaceContainerLowest: neutral[dark ? 12 : 0],
      surfaceContainerLow: neutral[dark ? 11 : 2],
      surfaceContainer: neutral[dark ? 11 : 2],
      surfaceContainerHigh: neutral[dark ? 10 : 3],
      surfaceContainerHighest: neutral[dark ? 10 : 3],
      inverseSurface: neutral[dark ? 3 : 10], onInverseSurface: neutral[dark ? 10 : 2],
      inversePrimary: primary[dark ? 8 : 4],
    );
  }
}
