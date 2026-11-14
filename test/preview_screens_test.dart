// README preview renderer.
//
// Renders real screens off-screen (no emulator required) and writes PNGs to
// build/preview. Disabled unless QINGNIAO_RENDER_PREVIEW=1, so the normal test
// run stays side-effect free.
//
//   $env:QINGNIAO_RENDER_PREVIEW = "1"
//   flutter test test/preview_screens_test.dart
//
// The host test engine ships no CJK font, so the previews use the bundled
// HarmonyOS Sans family (a selectable option in Appearance) instead of the
// platform default, which would render every glyph as a box.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/aurora/aurora_widgets.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/conversation_screen.dart';
import 'package:qingniao/messaging/home_shell.dart';
import 'package:qingniao/messaging/message_hub.dart';
import 'package:qingniao/messaging/message_repository.dart';
import 'package:qingniao/messaging/otp_screen.dart';
import 'package:qingniao/settings/navigation_appearance.dart';
import 'package:qingniao/settings/settings_screen.dart';

import 'support/fixture_message_repository.dart';

const _phone = Size(412, 915);

/// Set when the host emoji font is available for glyph fallback.
bool _emojiLoaded = false;

/// Bundled families exactly as pubspec.yaml declares them.
Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    final file = File(asset);
    if (!file.existsSync()) continue;
    loader.addFont(file.readAsBytes().then(ByteData.sublistView));
  }
  await loader.load();
}

/// MaterialIcons ships with the Flutter SDK, not with the app assets.
Future<void> _loadIconFont() async {
  final loader = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppStrings.initialize();
    AppStrings.language = 'zh';
    await _loadIconFont();
    await _loadFont('GoogleSans', ['assets/fonts/GoogleSans-Variable.ttf']);
    await _loadFont('HarmonyOSSans', [
      'assets/fonts/HarmonyOS_SansSC_Regular.ttf',
      'assets/fonts/HarmonyOS_SansSC_Medium.ttf',
      'assets/fonts/HarmonyOS_SansSC_Bold.ttf',
    ]);
    // The host has no emoji font; borrow the Windows one so fixture copy that
    // contains emoji does not render as tofu. It must be a separate family:
    // Flutter falls back per family, not per glyph inside one family.
    final emoji = Platform.environment['QINGNIAO_PREVIEW_EMOJI_FONT'] ??
        r'C:\Windows\Fonts\seguiemj.ttf';
    if (File(emoji).existsSync()) {
      await _loadFont('PreviewEmoji', [emoji]);
      _emojiLoaded = true;
    }
  });

  testWidgets('render README preview screens', (tester) async {
    if (Platform.environment['QINGNIAO_RENDER_PREVIEW'] != '1') return;

    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = FixtureMessageRepository();
    final hub = MessageHub(repository)..start();
    addTearDown(hub.dispose);

    final threads = await repository.conversations();
    final conversation = threads.firstWhere(
      (thread) => thread.displayName == '设计小组',
      orElse: () => threads.first,
    );

    for (final brightness in Brightness.values) {
      final suffix = brightness == Brightness.dark ? 'dark' : 'light';

      await _shoot(
        tester,
        name: 'home_inbox_$suffix',
        repository: repository,
        brightness: brightness,
        child: HomeShell(repository: repository, hub: hub),
      );
      await _shoot(
        tester,
        name: 'conversation_$suffix',
        repository: repository,
        brightness: brightness,
        child: ConversationScreen(
          repository: repository,
          hub: hub,
          thread: conversation,
        ),
      );
      await _shoot(
        tester,
        name: 'otp_$suffix',
        repository: repository,
        brightness: brightness,
        // Same chrome as HomeShell's second tab, so the capture is opaque.
        child: AuroraScaffold(body: OtpScreen(repository: repository, hub: hub)),
      );
      await _shoot(
        tester,
        name: 'settings_$suffix',
        repository: repository,
        brightness: brightness,
        child: AuroraScaffold(
          body: SettingsScreen(repository: repository, hub: hub),
        ),
      );
      await _shoot(
        tester,
        name: 'navigation_appearance_$suffix',
        repository: repository,
        brightness: brightness,
        size: const Size(412, 520),
        child: const AuroraScaffold(body: NavigationAppearance()),
      );
    }
  });
}

Future<void> _shoot(
  WidgetTester tester, {
  required String name,
  required Widget child,
  required MessageRepository repository,
  required Brightness brightness,
  Size size = _phone,
}) async {
  tester.view.physicalSize = size;

  final boundaryKey = GlobalKey();
  var theme = buildAuroraTheme(
    brightness: brightness,
    appearance: const AuroraAppearance(fontFamily: 'harmony'),
  );
  if (_emojiLoaded) {
    const fallback = ['HarmonyOSSans', 'PreviewEmoji'];
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamilyFallback: fallback),
      chipTheme: theme.chipTheme.copyWith(
        labelStyle: theme.chipTheme.labelStyle?.copyWith(
          fontFamilyFallback: fallback,
        ),
        secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
          fontFamilyFallback: fallback,
        ),
      ),
    );
  }

  await tester.pumpWidget(
    AppScope(
      settings: AppSettings(repository: repository),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: RepaintBoundary(key: boundaryKey, child: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final target = File('build/preview/$name.png');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });

  debugPrint('rendered build/preview/$name.png');
  await tester.pumpWidget(const SizedBox());
}
