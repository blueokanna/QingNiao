import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_settings.dart';
import 'aurora/aurora_engine.dart';
import 'aurora/aurora_shapes.dart';
import 'aurora/aurora_backdrop.dart';
import 'aurora/aurora_theme.dart';
import 'messaging/home_shell.dart';
import 'messaging/message_hub.dart';
import 'messaging/message_repository.dart';

class QingniaoApp extends StatefulWidget {
  const QingniaoApp({
    super.key,
    required this.repository,
    required this.settings,
  });

  final MessageRepository repository;
  final AppSettings settings;

  @override
  State<QingniaoApp> createState() => _QingniaoAppState();
}

class _QingniaoAppState extends State<QingniaoApp>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _systemReduceMotion = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AuroraEngine.instance.attach(this);
    _applyMotion();
    widget.settings.addListener(_onSettings);
  }

  void _onSettings() => _applyMotion();

  @override
  void didHaveMemoryPressure() {
    AuroraShapes.clearCache();
    PaintingBinding.instance.imageCache.clear();
  }

  void _applyMotion() {
    final settings = widget.settings;
    AuroraEngine.instance.configure(
      motion: settings.motionLevel,
      reduce:
          _systemReduceMotion ||
          settings.motionLevel == AuroraMotionLevel.reduced,
      backdrop: true,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AuroraEngine.instance.resume();
      widget.settings.refreshSystemSeed();
    } else {
      AuroraEngine.instance.pause();
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    WidgetsBinding.instance.removeObserver(this);
    AuroraEngine.instance.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) {
        final settings = widget.settings;
        return AppScope(
          settings: settings,
          child: MaterialApp(
            title: tr("Qingniao"),
            debugShowCheckedModeBanner: false,
            locale: settings.localeCode == 'system'
                ? null
                : Locale(settings.localeCode),
            supportedLocales: AppStrings.locales,
            localeListResolutionCallback: AppStrings.resolve,
            localizationsDelegates: const [
              AppStringsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildAuroraTheme(
              brightness: Brightness.light,
              appearance: settings.appearance,
            ),
            darkTheme: buildAuroraTheme(
              brightness: Brightness.dark,
              appearance: settings.appearance,
            ),
            themeMode: settings.themeMode,
            builder: (context, child) {
              final reduce = MediaQuery.disableAnimationsOf(context);
              if (reduce != _systemReduceMotion) {
                _systemReduceMotion = reduce;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _applyMotion();
                });
              }
              AuroraEngine.instance.setRefreshRate(
                View.of(context).display.refreshRate,
              );
              final media = MediaQuery.of(context);
              final brightness = Theme.of(context).brightness;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: brightness == Brightness.dark
                    ? SystemUiOverlayStyle.light.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.transparent,
                      )
                    : SystemUiOverlayStyle.dark.copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: Colors.transparent,
                      ),
                child: MediaQuery(
                  data: media.copyWith(
                    textScaler: _effectiveTextScaler(
                      media.textScaler,
                      settings.fontScale,
                    ),
                  ),
                  child: AuroraBackdropScope(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const AuroraBackdrop(),
                        child ?? const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              );
            },
            home: RootGate(repository: widget.repository),
          ),
        );
      },
    );
  }
}

/// Applies the user's font-scale setting on top of the platform scaler.
///
/// The platform scaler is left untouched when the factor is neutral, so the
/// default path keeps the exact system behaviour and rebuilds triggered by this
/// builder do not invalidate every text widget.
TextScaler _effectiveTextScaler(TextScaler system, double factor) {
  if (!factor.isFinite || factor == 1) return system;
  return _AdjustedTextScaler(system, factor);
}

/// Multiplies the platform scaler by the user's factor.
///
/// The platform scaler can be nonlinear (Android 14+), so the factor is applied
/// per font size instead of collapsing everything into one ratio.
class _AdjustedTextScaler extends TextScaler {
  const _AdjustedTextScaler(this.system, this.factor);

  final TextScaler system;
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;

  // TextScaler declares this as an abstract member, so a concrete subclass must
  // implement it even though the API itself is deprecated. Reporting the product
  // keeps callers that still read it on the same ratio as [scale].
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => system.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _AdjustedTextScaler &&
      other.system == system &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(system, factor);

  @override
  String toString() => '_AdjustedTextScaler($system, ${factor}x)';
}

class RootGate extends StatefulWidget {
  const RootGate({super.key, required this.repository});

  final MessageRepository repository;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late final MessageHub _hub = MessageHub(widget.repository);
  @override
  void dispose() {
    _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HomeShell(repository: widget.repository, hub: _hub);
  }
}
