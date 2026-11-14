import 'package:qingniao/l10n/app_strings.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/messaging/conversation_screen.dart';

import 'support/fixture_message_repository.dart';

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

  for (final brightness in Brightness.values) {
    testWidgets(
      '\u4f1a\u8bdd\u9875\u5728 ${brightness.name} \u4e3b\u9898\u4e0b\u6e32\u67d3',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repository = FixtureMessageRepository();
        final hub = MessageHub(repository);
        final thread = (await repository.conversations()).firstWhere(
          (item) => item.displayName == '\u8bbe\u8ba1\u5c0f\u7ec4',
        );
        expect(thread.isGroup, isTrue);
        final boundaryKey = GlobalKey();
        var theme = buildAuroraTheme(
          brightness: brightness,
          appearance: const AuroraAppearance(),
        );
        if (Platform.environment['QINGNIAO_PREVIEW_FONT'] != null) {
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(
              fontFamily: 'PreviewFont',
              fontFamilyFallback: const ['PreviewFont'],
            ),
          );
        }

        await tester.pumpWidget(
          AppScope(
            settings: AppSettings(repository: repository),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: RepaintBoundary(
                key: boundaryKey,
                child: ConversationScreen(
                  repository: repository,
                  hub: hub,
                  thread: thread,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('\u8bc4\u5ba1'), findsWidgets);

        if (Platform.environment['QINGNIAO_RENDER_PREVIEW'] == '1') {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final target = File(
              'build/verification/conversation_${brightness.name}.png',
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
