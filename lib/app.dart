import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_settings.dart';
import 'aurora/aurora_engine.dart';
import 'aurora/aurora_shapes.dart';
import 'aurora/aurora_theme.dart';
import 'aurora/aurora_widgets.dart';
import 'messaging/home_shell.dart';
import 'messaging/message_hub.dart';
import 'messaging/message_repository.dart';
import 'messaging/models.dart';
import 'onboarding/onboarding_screen.dart';

/// 应用根：主题、全局时钟与引导流程。
class QingniaoApp extends StatefulWidget {
  const QingniaoApp({super.key, required this.repository, required this.settings});

  final MessageRepository repository;
  final AppSettings settings;

  @override
  State<QingniaoApp> createState() => _QingniaoAppState();
}

class _QingniaoAppState extends State<QingniaoApp> with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    AuroraEngine.instance.attach(this);
    _applyMotion();
    widget.settings.addListener(_onSettings);
  }

  void _onSettings() => _applyMotion();

  void _applyMotion() {
    final settings = widget.settings;
    AuroraEngine.instance.configure(
      motion: settings.lowPowerAurora ? AuroraMotionLevel.reduced : settings.motionLevel,
      reduce: settings.motionLevel == AuroraMotionLevel.reduced,
    );
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
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
            title: '青鸟短信',
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: const [
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
              if (reduce != AuroraEngine.instance.reduceMotion) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  AuroraEngine.instance.configure(
                    motion: settings.motionLevel,
                    reduce: reduce,
                  );
                });
              }
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
                  data: media.copyWith(textScaler: TextScaler.linear(settings.fontScale)),
                  child: child ?? const SizedBox.shrink(),
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

/// 启动闸门：读取权限状态，决定进入引导还是主界面。
class RootGate extends StatefulWidget {
  const RootGate({super.key, required this.repository});

  final MessageRepository repository;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late final MessageHub _hub = MessageHub(widget.repository);
  AccessState _access = const AccessState();
  bool _loading = true;
  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final access = await widget.repository.access();
      if (!mounted) return;
      setState(() {
        _access = access;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AuroraScaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AuroraBloom(size: 132),
              const SizedBox(height: 18),
              Text('青鸟正在苏醒', style: context.texts.titleMedium),
              const SizedBox(height: 10),
              const AuroraLoading(),
            ],
          ),
        ),
      );
    }
    if (!_access.ready && !_skipped) {
      return OnboardingScreen(
        repository: widget.repository,
        onReady: _check,
        onSkip: () => setState(() => _skipped = true),
      );
    }
    return HomeShell(repository: widget.repository, hub: _hub);
  }
}
