import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/messaging/conversation_screen.dart';

import 'support/fixture_message_repository.dart';

import 'package:qingniao/messaging/message_hub.dart';
import 'package:qingniao/messaging/models.dart';
import 'package:qingniao/messaging/trash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppStrings.initialize();
    AppStrings.language = 'zh';
  });

  Future<ThreadSummary> firstThread(
    FixtureMessageRepository repository,
  ) async => (await repository.conversations()).first;

  testWidgets(
    '\u4f1a\u8bdd\u9875\u6e32\u67d3\u6d88\u606f\u5e76\u80fd\u53d1\u9001\u65b0\u77ed\u4fe1',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = FixtureMessageRepository();
      final hub = MessageHub(repository);
      final thread = await firstThread(repository);
      await tester.pumpWidget(
        AppScope(
          settings: AppSettings(repository: repository),
          child: MaterialApp(
            theme: buildAuroraTheme(
              brightness: Brightness.light,
              appearance: const AuroraAppearance(),
            ),
            home: ConversationScreen(
              repository: repository,
              hub: hub,
              thread: thread,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byType(TextField),
        '\u665a\u4e0a\u597d，\u6781\u5149',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.textContaining('\u665a\u4e0a\u597d，\u6781\u5149'),
        findsWidgets,
      );
      hub.dispose();
    },
  );

  testWidgets(
    '\u56de\u6536\u7ad9\u80fd\u5217\u51fa\u5e76\u6062\u590d\u6d88\u606f',
    (tester) async {
      final repository = FixtureMessageRepository();
      await repository.hide(1);
      await tester.pumpWidget(
        AppScope(
          settings: AppSettings(repository: repository),
          child: MaterialApp(
            theme: buildAuroraTheme(
              brightness: Brightness.dark,
              appearance: const AuroraAppearance(),
            ),
            home: TrashScreen(repository: repository),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('\u6062\u590d'), findsWidgets);
      await tester.tap(find.text('\u6062\u590d').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '\u7a84\u5c4f\u4e0e\u5927\u5b57\u4f53\u4e0b\u64b0\u5199\u680f\u4ecd\u53ef\u7528',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = FixtureMessageRepository();
      final hub = MessageHub(repository);
      final thread = await firstThread(repository);
      await tester.pumpWidget(
        AppScope(
          settings: AppSettings(repository: repository),
          child: MaterialApp(
            theme: buildAuroraTheme(
              brightness: Brightness.light,
              appearance: const AuroraAppearance(),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.6),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: ConversationScreen(
              repository: repository,
              hub: hub,
              thread: thread,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      hub.dispose();
    },
  );
}
