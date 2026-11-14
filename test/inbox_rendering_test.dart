import 'package:qingniao/l10n/app_strings.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/aurora/aurora_widgets.dart';

import 'support/fixture_message_repository.dart';

import 'package:qingniao/messaging/inbox_screen.dart';
import 'package:qingniao/messaging/otp_screen.dart';
import 'package:qingniao/messaging/message_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppStrings.initialize();
    AppStrings.language = 'zh';
  });

  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final fontPath = Platform.environment['QINGNIAO_PREVIEW_FONT'];
    if (fontPath != null && File(fontPath).existsSync()) {
      final loader = FontLoader('PreviewFont')
        ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });

  for (final otp in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '\u6536\u4ef6\u7bb1\u5728 ${otp ? "otp" : "inbox"} ${brightness.name} \u4e3b\u9898\u4e0b\u6e32\u67d3\u4e14\u65e0\u5e03\u5c40\u5f02\u5e38',
        (tester) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final repository = FixtureMessageRepository();
          final hub = MessageHub(repository)..start();
          final boundaryKey = GlobalKey();
          var theme = buildAuroraTheme(
            brightness: brightness,
            appearance: const AuroraAppearance(),
          );
          if (Platform.environment['QINGNIAO_PREVIEW_FONT'] != null) {
            theme = theme.copyWith(
              chipTheme: theme.chipTheme.copyWith(
                labelStyle: theme.chipTheme.labelStyle?.copyWith(
                  fontFamily: 'PreviewFont',
                ),
                secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle
                    ?.copyWith(fontFamily: 'PreviewFont'),
              ),
              textTheme: theme.textTheme.apply(
                fontFamily: 'PreviewFont',
                fontFamilyFallback: const ['PreviewFont'],
              ),
            );
          }
          final previousShadows = debugDisableShadows;
          addTearDown(() => debugDisableShadows = previousShadows);
          await tester.pumpWidget(
            AppScope(
              settings: AppSettings(repository: repository),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: theme,
                home: RepaintBoundary(
                  key: boundaryKey,
                  child: AuroraScaffold(
                    body: otp
                        ? OtpScreen(repository: repository, hub: hub)
                        : InboxScreen(repository: repository, hub: hub),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          if (!otp) {
            expect(
              find.text(
                '\u9752\u9e1f\u8854\u661f\u81f3\uff0c\u5c3a\u7d20\u5bc4\u5fc3\u95f4',
              ),
              findsOneWidget,
            );
            expect(
              find.textContaining('\u5de5\u5546\u94f6\u884c'),
              findsWidgets,
            );
          }

          if (Platform.environment['QINGNIAO_RENDER_PREVIEW'] == '1') {
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final target = File(
                'build/verification/${otp ? 'otp' : 'inbox'}_${brightness.name}.png',
              );
              await target.parent.create(recursive: true);
              await target.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
          hub.dispose();
        },
      );
    }
  }
}
