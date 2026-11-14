import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aurora_motion.dart';
import '../design/android_palette.dart';
import '../design/bundled_fonts.dart';

abstract final class AuroraPalettes {
  static const jade = Color(0xFF0E7C6B);
  static const aurora = Color(0xFF5B6CFF);
  static const lagoon = Color(0xFF1677A8);
  static const dawn = Color(0xFFB45A34);
  static const plum = Color(0xFF8E4EC6);
  static const graphite = Color(0xFF4B5563);

  static const seeds = <String, Color>{
    '青碧': jade,
    '极光': aurora,
    '湖水': lagoon,
    '晨曦': dawn,
    '梅子': plum,
    '石墨': graphite,
  };
}

@immutable
class AuroraColors extends ThemeExtension<AuroraColors> {
  const AuroraColors({
    required this.auroraA,
    required this.auroraB,
    required this.auroraC,
    required this.glow,
    required this.otp,
    required this.otpSoft,
    required this.success,
    required this.warning,
    required this.hairline,
    required this.glass,
    required this.glassStrong,
    required this.incomingBubble,
    required this.incomingText,
    required this.outgoingA,
    required this.outgoingB,
    required this.outgoingText,
    required this.navSurface,
    required this.star,
  });

  final Color auroraA;
  final Color auroraB;
  final Color auroraC;
  final Color glow;
  final Color otp;
  final Color otpSoft;
  final Color success;
  final Color warning;
  final Color hairline;
  final Color glass;
  final Color glassStrong;
  final Color incomingBubble;
  final Color incomingText;
  final Color outgoingA;
  final Color outgoingB;
  final Color outgoingText;
  final Color navSurface;
  final Color star;

  List<Color> get aurora => [auroraA, auroraB, auroraC];

  LinearGradient get outgoingGradient => LinearGradient(
    colors: [outgoingA, outgoingB],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  LinearGradient get heroGradient => LinearGradient(
    colors: [auroraA, auroraB],
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
  );

  @override
  AuroraColors copyWith({
    Color? auroraA,
    Color? auroraB,
    Color? auroraC,
    Color? glow,
    Color? otp,
    Color? otpSoft,
    Color? success,
    Color? warning,
    Color? hairline,
    Color? glass,
    Color? glassStrong,
    Color? incomingBubble,
    Color? incomingText,
    Color? outgoingA,
    Color? outgoingB,
    Color? outgoingText,
    Color? navSurface,
    Color? star,
  }) {
    return AuroraColors(
      auroraA: auroraA ?? this.auroraA,
      auroraB: auroraB ?? this.auroraB,
      auroraC: auroraC ?? this.auroraC,
      glow: glow ?? this.glow,
      otp: otp ?? this.otp,
      otpSoft: otpSoft ?? this.otpSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      hairline: hairline ?? this.hairline,
      glass: glass ?? this.glass,
      glassStrong: glassStrong ?? this.glassStrong,
      incomingBubble: incomingBubble ?? this.incomingBubble,
      incomingText: incomingText ?? this.incomingText,
      outgoingA: outgoingA ?? this.outgoingA,
      outgoingB: outgoingB ?? this.outgoingB,
      outgoingText: outgoingText ?? this.outgoingText,
      navSurface: navSurface ?? this.navSurface,
      star: star ?? this.star,
    );
  }

  @override
  AuroraColors lerp(covariant AuroraColors? other, double t) {
    if (other == null) return this;
    return AuroraColors(
      auroraA: Color.lerp(auroraA, other.auroraA, t)!,
      auroraB: Color.lerp(auroraB, other.auroraB, t)!,
      auroraC: Color.lerp(auroraC, other.auroraC, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      otp: Color.lerp(otp, other.otp, t)!,
      otpSoft: Color.lerp(otpSoft, other.otpSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      incomingBubble: Color.lerp(incomingBubble, other.incomingBubble, t)!,
      incomingText: Color.lerp(incomingText, other.incomingText, t)!,
      outgoingA: Color.lerp(outgoingA, other.outgoingA, t)!,
      outgoingB: Color.lerp(outgoingB, other.outgoingB, t)!,
      outgoingText: Color.lerp(outgoingText, other.outgoingText, t)!,
      navSurface: Color.lerp(navSurface, other.navSurface, t)!,
      star: Color.lerp(star, other.star, t)!,
    );
  }
}

@immutable
class AuroraAppearance {
  const AuroraAppearance({
    this.seed = AuroraPalettes.jade,
    this.dynamicSeed,
    this.useDynamic = false,
    this.bubbleStyle = AuroraBubbleStyle.soft,
    this.morphShapes = true,
    this.amoled = false,
    this.fontFamily = 'system',
    this.systemPalette,
  });

  final Color seed;
  final Color? dynamicSeed;
  final bool useDynamic;
  final AuroraBubbleStyle bubbleStyle;
  final bool morphShapes;
  final bool amoled;
  final String fontFamily;
  final AndroidPalette? systemPalette;

  Color get effectiveSeed => useDynamic ? (dynamicSeed ?? seed) : seed;

  AuroraAppearance copyWith({
    Color? seed,
    Color? dynamicSeed,
    bool? useDynamic,
    AuroraBubbleStyle? bubbleStyle,
    bool? morphShapes,
    bool? amoled,
    String? fontFamily,
    AndroidPalette? systemPalette,
  }) => AuroraAppearance(
    seed: seed ?? this.seed,
    dynamicSeed: dynamicSeed ?? this.dynamicSeed,
    useDynamic: useDynamic ?? this.useDynamic,
    bubbleStyle: bubbleStyle ?? this.bubbleStyle,
    morphShapes: morphShapes ?? this.morphShapes,
    amoled: amoled ?? this.amoled,
    fontFamily: fontFamily ?? this.fontFamily,
    systemPalette: systemPalette ?? this.systemPalette,
  );
}

enum AuroraBubbleStyle { soft, capsule, cookie }

ThemeData buildAuroraTheme({
  required Brightness brightness,
  required AuroraAppearance appearance,
}) {
  final seed = appearance.effectiveSeed;
  var scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final dark = brightness == Brightness.dark;
  if (appearance.useDynamic) {
    scheme = appearance.systemPalette?.applyTo(scheme) ?? scheme;
  }
  if (dark && appearance.amoled) {
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xff080808),
      surfaceContainer: const Color(0xff101010),
    );
  }
  final aurora = _auroraColors(scheme, dark);
  final radius = appearance.bubbleStyle == AuroraBubbleStyle.capsule
      ? 30.0
      : 26.0;

  final baseText = dark
      ? Typography.material2021().white
      : Typography.material2021().black;
  final textTheme = baseText.copyWith(
    displayLarge: baseText.displayLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -1.6,
      height: 1.04,
    ),
    displayMedium: baseText.displayMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -1.2,
      height: 1.08,
    ),
    headlineLarge: baseText.headlineLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -.7,
      height: 1.18,
    ),
    headlineMedium: baseText.headlineMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -.5,
      height: 1.2,
    ),
    headlineSmall: baseText.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -.2,
      height: 1.24,
    ),
    titleLarge: baseText.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -.2,
      height: 1.3,
    ),
    titleMedium: baseText.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -.1,
      height: 1.32,
    ),
    titleSmall: baseText.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: .1,
    ),
    bodyLarge: baseText.bodyLarge?.copyWith(height: 1.55, letterSpacing: .1),
    bodyMedium: baseText.bodyMedium?.copyWith(height: 1.55, letterSpacing: .1),
    bodySmall: baseText.bodySmall?.copyWith(height: 1.5, letterSpacing: .2),
    labelLarge: baseText.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: .2,
    ),
    labelMedium: baseText.labelMedium?.copyWith(
      fontWeight: FontWeight.w500,
      letterSpacing: .3,
    ),
    labelSmall: baseText.labelSmall?.copyWith(
      fontWeight: FontWeight.w500,
      letterSpacing: .4,
    ),
  );

  final border = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(radius),
  );
  final buttonBorder = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(22),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme.apply(
      fontFamily: BundledFonts.families[appearance.fontFamily],
      fontFamilyFallback: appearance.fontFamily == 'system'
          ? null
          : const ['HarmonyOSSans'],
    ),
    fontFamily: BundledFonts.families[appearance.fontFamily],
    fontFamilyFallback: appearance.fontFamily == 'system'
        ? null
        : const ['HarmonyOSSans'],
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: scheme.surface,
    dividerColor: aurora.hairline,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    extensions: [aurora],
    pageTransitionsTheme: AuroraPageTransitionsTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: aurora.glass,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: border,
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(32)),
      titleTextStyle: textTheme.headlineSmall?.copyWith(
        color: scheme.onSurface,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
      elevation: 0,
      showDragHandle: false,
      constraints: const BoxConstraints(maxWidth: 680),
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(20)),
      actionTextColor: scheme.inversePrimary,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(56, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: buttonBorder,
        elevation: 0,
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: buttonBorder,
        side: BorderSide(color: aurora.hairline),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(10),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 2,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
      extendedTextStyle: textTheme.labelLarge,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: aurora.glass,
      selectedColor: scheme.secondaryContainer,
      disabledColor: aurora.glass,
      surfaceTintColor: Colors.transparent,
      side: BorderSide.none,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
      labelStyle: textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(
        color: scheme.onSecondaryContainer,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: aurora.glassStrong,
      hintStyle: textTheme.bodyLarge?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: .7),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(
          color: scheme.primary.withValues(alpha: .55),
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: scheme.error.withValues(alpha: .6)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: scheme.error, width: 1.4),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(22)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: textTheme.titleSmall,
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: aurora.hairline,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : aurora.glassStrong,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: aurora.glassStrong,
      circularTrackColor: aurora.glassStrong,
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: scheme.error,
      textColor: scheme.onError,
      textStyle: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: .22),
      selectionHandleColor: scheme.primary,
    ),
  );
}

AuroraColors _auroraColors(ColorScheme scheme, bool dark) {
  final surface = scheme.surface;
  final primary = scheme.primary;
  final tertiary = scheme.tertiary;
  final secondary = scheme.secondary;
  final glow = Color.alphaBlend(
    primary.withValues(alpha: dark ? .22 : .14),
    surface,
  );

  return AuroraColors(
    auroraA: dark ? _lift(primary, .12) : _deepen(primary, .06),
    auroraB: dark ? _lift(tertiary, .18) : tertiary,
    auroraC: dark ? _lift(secondary, .08) : secondary,
    glow: glow,
    otp: dark ? _lift(tertiary, .28) : _deepen(tertiary, .16),
    otpSoft: Color.alphaBlend(
      tertiary.withValues(alpha: dark ? .18 : .12),
      surface,
    ),
    success: dark ? const Color(0xFF7FDDB6) : const Color(0xFF1E7A56),
    warning: dark ? const Color(0xFFFFC46B) : const Color(0xFF9A5B00),
    hairline: scheme.outlineVariant.withValues(alpha: dark ? .34 : .5),
    glass: Color.alphaBlend(
      (dark ? Colors.white : scheme.surfaceContainerHighest).withValues(
        alpha: dark ? .055 : .5,
      ),
      dark ? surface : Colors.white,
    ),
    glassStrong: Color.alphaBlend(
      (dark ? Colors.white : scheme.surfaceContainerHigh).withValues(
        alpha: dark ? .09 : .72,
      ),
      dark ? surface : Colors.white,
    ),
    incomingBubble: dark
        ? Color.alphaBlend(Colors.white.withValues(alpha: .075), surface)
        : Color.alphaBlend(
            scheme.surfaceContainerHigh.withValues(alpha: .9),
            Colors.white,
          ),
    incomingText: scheme.onSurface,
    outgoingA: dark
        ? _lift(scheme.primaryContainer, .04)
        : scheme.primary,
    outgoingB: dark
        ? _lift(
            Color.lerp(scheme.primaryContainer, scheme.secondaryContainer, .6)!,
            .04,
          )
        : Color.lerp(scheme.primary, scheme.secondary, .55)!,
    outgoingText: dark ? scheme.onPrimaryContainer : scheme.onPrimary,
    navSurface: Color.alphaBlend(
      (dark
          ? Colors.white.withValues(alpha: .08)
          : Colors.white.withValues(alpha: .78)),
      dark ? surface : scheme.surfaceContainerLow,
    ),
    star: dark
        ? Colors.white.withValues(alpha: .5)
        : scheme.primary.withValues(alpha: .28),
  );
}

Color _lift(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Color _deepen(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

extension AuroraThemeContext on BuildContext {
  AuroraColors get aurora =>
      Theme.of(this).extension<AuroraColors>() ?? _fallbackAurora;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
}

final AuroraColors _fallbackAurora = _auroraColors(
  ColorScheme.fromSeed(seedColor: AuroraPalettes.jade),
  false,
);
