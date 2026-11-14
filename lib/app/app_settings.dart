import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../aurora/aurora_engine.dart';
import '../aurora/aurora_theme.dart';
import '../messaging/message_repository.dart';
import '../design/android_palette.dart';

enum AuroraThemePreference { system, light, dark }

enum ThreadSwipeAction { trash, read, archive, pin, none }

String swipeActionLabel(ThreadSwipeAction action) => switch (action) {
  ThreadSwipeAction.trash => tr('Move to trash'),
  ThreadSwipeAction.read => tr('Mark as read'),
  ThreadSwipeAction.archive => tr('Archive'),
  ThreadSwipeAction.pin => tr('Pin conversation'),
  ThreadSwipeAction.none => tr('Disabled'),
};

class AppSettings extends ChangeNotifier {
  AppSettings({MessageRepository? repository}) : _repository = repository;

  final MessageRepository? _repository;
  bool _disposed = false;

  AuroraThemePreference themePreference = AuroraThemePreference.system;
  Color seed = AuroraPalettes.jade;
  Color? systemSeed;
  bool useDynamic = false;
  AuroraBubbleStyle bubbleStyle = AuroraBubbleStyle.soft;
  bool morphShapes = true;
  AuroraMotionLevel motionLevel = AuroraMotionLevel.full;
  double fontScale = 1;
  bool deliveryReports = true;
  bool notifications = true;
  bool showPreview = true;
  bool recycleReadCodes = true;
  String signature = '';
  int trashRetentionDays = 30;
  bool sendDelay = false;
  bool lowPowerAurora = false;
  bool fluidCloud = true;
  bool amoled = false;
  String fontFamily = 'system';
  String localeCode = 'system';
  String launcherIcon = 'bird';
  ThreadSwipeAction swipeLeft = ThreadSwipeAction.trash;
  ThreadSwipeAction swipeRight = ThreadSwipeAction.read;
  AndroidPalette? systemPalette;

  ThemeMode get themeMode => switch (themePreference) {
    AuroraThemePreference.system => ThemeMode.system,
    AuroraThemePreference.light => ThemeMode.light,
    AuroraThemePreference.dark => ThemeMode.dark,
  };

  AuroraAppearance get appearance => AuroraAppearance(
    seed: seed,
    dynamicSeed: systemSeed,
    useDynamic: useDynamic,
    bubbleStyle: bubbleStyle,
    morphShapes: morphShapes,
    amoled: amoled,
    fontFamily: fontFamily,
    systemPalette: systemPalette,
  );

  static Future<AppSettings> load(MessageRepository repository) async {
    final settings = AppSettings(repository: repository);
    try {
      final values = await repository.settingsAll();
      settings._apply(values);
      final seedHex = await repository.systemSeed();
      settings.systemSeed = _colorFromHex(seedHex);
      settings.systemPalette = AndroidPalette.fromMap(
        await repository.invoke<Map>('systemPalette'),
      );
    } catch (_) {}
    return settings;
  }

  void _apply(Map<String, String> values) {
    swipeLeft =
        ThreadSwipeAction.values
            .where((v) => v.name == values['swipeLeft'])
            .firstOrNull ??
        ThreadSwipeAction.trash;
    swipeRight =
        ThreadSwipeAction.values
            .where((v) => v.name == values['swipeRight'])
            .firstOrNull ??
        ThreadSwipeAction.read;
    localeCode = AppStrings.languageCodes.contains(values['locale'])
        ? values['locale']!
        : 'system';
    themePreference = switch (values['themeMode']) {
      'light' => AuroraThemePreference.light,
      'dark' => AuroraThemePreference.dark,
      _ => AuroraThemePreference.system,
    };
    final seedName = AppStrings.paletteKey(values['seed']);
    seed = AuroraPalettes.seeds[seedName] ?? AuroraPalettes.jade;
    useDynamic = values['useDynamic'] == 'true';
    bubbleStyle = switch (values['bubble']) {
      'capsule' => AuroraBubbleStyle.capsule,
      'cookie' => AuroraBubbleStyle.cookie,
      _ => AuroraBubbleStyle.soft,
    };
    morphShapes = values['morph'] != 'false';
    motionLevel = switch (values['motion']) {
      'balanced' => AuroraMotionLevel.balanced,
      'reduced' => AuroraMotionLevel.reduced,
      _ => AuroraMotionLevel.full,
    };
    fontScale =
        double.tryParse(values['fontScale'] ?? '')?.clamp(.85, 1.25) ?? 1;
    deliveryReports = values['delivery'] != 'false';
    notifications = values['notifications'] != 'false';
    showPreview = values['preview'] != 'false';
    recycleReadCodes = values['recycleReadCodes'] != 'false';
    signature = values['signature'] ?? '';
    trashRetentionDays = int.tryParse(values['trashDays'] ?? '') ?? 30;
    sendDelay = values['sendDelay'] == 'true';
    lowPowerAurora = values['lowPowerAurora'] == 'true';
    fluidCloud = values['fluidCloud'] != 'false';
    amoled = values['amoled'] == 'true';
    launcherIcon =
        const ['bird', 'leaf', 'chat'].contains(values['launcherIcon'])
        ? values['launcherIcon']!
        : 'bird';
    fontFamily = switch (values['fontFamily']) {
      'harmony' => 'harmony',
      'google' => 'google',
      _ => 'system',
    };
  }

  Future<void> refreshSystemSeed() async {
    try {
      final nextSeed = _colorFromHex(await _repository?.systemSeed());
      final nextPalette = AndroidPalette.fromMap(
        await _repository?.invoke<Map>('systemPalette'),
      );
      if (_disposed) return;
      systemSeed = nextSeed;
      systemPalette = nextPalette;
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void update(VoidCallback change) {
    change();
    notifyListeners();
    _persist();
  }

  void setTheme(AuroraThemePreference value) =>
      update(() => themePreference = value);

  void setSwipe({required bool left, required ThreadSwipeAction action}) =>
      update(() {
        if (left) {
          swipeLeft = action;
        } else {
          swipeRight = action;
        }
      });

  void setSeed(String name) =>
      update(() => seed = AuroraPalettes.seeds[name] ?? AuroraPalettes.jade);

  void setDynamic(bool value) => update(() => useDynamic = value);

  void setBubble(AuroraBubbleStyle value) => update(() => bubbleStyle = value);

  void setMorph(bool value) => update(() => morphShapes = value);

  void setMotion(AuroraMotionLevel value) => update(() => motionLevel = value);

  void setFontScale(double value) =>
      update(() => fontScale = value.clamp(.85, 1.25));

  void setDelivery(bool value) => update(() => deliveryReports = value);

  void setNotifications(bool value) => update(() => notifications = value);

  void setRecycleReadCodes(bool value) =>
      update(() => recycleReadCodes = value);

  void setPreview(bool value) => update(() => showPreview = value);

  void setSignature(String value) => update(() => signature = value);

  void setTrashDays(int value) => update(() => trashRetentionDays = value);

  void setSendDelay(bool value) => update(() => sendDelay = value);

  void setLowPower(bool value) => update(() => lowPowerAurora = value);

  void setFluidCloud(bool value) => update(() => fluidCloud = value);
  void setAmoled(bool value) => update(() {
    amoled = value;
    if (value) themePreference = AuroraThemePreference.dark;
  });
  void setFontFamily(String value) => update(
    () => fontFamily = const ['system', 'harmony', 'google'].contains(value)
        ? value
        : 'system',
  );
  void setLocale(String value) => update(() {
    localeCode = AppStrings.languageCodes.contains(value) ? value : 'system';
  });
  Future<void> setLauncherIcon(String value) async {
    await _repository?.invoke('setLauncherIcon', {'icon': value});
    launcherIcon = value;
    notifyListeners();
  }

  void _persist() {
    final repository = _repository;
    if (repository == null) return;
    final values = <String, String>{
      'swipeLeft': swipeLeft.name,
      'swipeRight': swipeRight.name,
      'locale': localeCode,
      'themeMode': switch (themePreference) {
        AuroraThemePreference.system => 'system',
        AuroraThemePreference.light => 'light',
        AuroraThemePreference.dark => 'dark',
      },
      'seed': AuroraPalettes.seeds.entries
          .firstWhere(
            (entry) => entry.value == seed,
            orElse: () => const MapEntry("PANTONE 3295 C", AuroraPalettes.jade),
          )
          .key,
      'useDynamic': '$useDynamic',
      'bubble': switch (bubbleStyle) {
        AuroraBubbleStyle.soft => 'soft',
        AuroraBubbleStyle.capsule => 'capsule',
        AuroraBubbleStyle.cookie => 'cookie',
      },
      'morph': '$morphShapes',
      'motion': switch (motionLevel) {
        AuroraMotionLevel.full => 'full',
        AuroraMotionLevel.balanced => 'balanced',
        AuroraMotionLevel.reduced => 'reduced',
      },
      'fontScale': fontScale.toStringAsFixed(2),
      'delivery': '$deliveryReports',
      'notifications': '$notifications',
      'preview': '$showPreview',
      'recycleReadCodes': '$recycleReadCodes',
      'signature': signature,
      'trashDays': '$trashRetentionDays',
      'sendDelay': '$sendDelay',
      'lowPowerAurora': '$lowPowerAurora',
      'fluidCloud': '$fluidCloud',
      'amoled': '$amoled',
      'fontFamily': fontFamily,
    };
    for (final entry in values.entries) {
      repository.settingsSet(entry.key, entry.value).catchError((_) {});
    }
  }
}

class AppScope extends InheritedNotifier<AppSettings> {
  const AppScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, tr("AppScope is not mounted"));
    return scope!.notifier!;
  }

  static AppSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;
}

Color? _colorFromHex(String? value) {
  if (value == null) return null;
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}
