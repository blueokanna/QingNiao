import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/messaging/conversation_screen.dart';
import 'package:qingniao/messaging/demo_repository.dart';
import 'package:qingniao/messaging/message_hub.dart';
import 'package:qingniao/messaging/models.dart';
import 'package:qingniao/messaging/trash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThreadSummary> firstThread(DemoMessageRepository repository) async =>
      (await repository.conversations()).first;

  testWidgets('会话页渲染消息并能发送新短信', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = DemoMessageRepository();
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
          home: ConversationScreen(repository: repository, hub: hub, thread: thread),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), '晚上好，极光');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('晚上好，极光'), findsWidgets);
    hub.dispose();
  });

  testWidgets('回收站能列出并恢复消息', (tester) async {
    final repository = DemoMessageRepository();
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
    expect(find.text('恢复'), findsWidgets);
    await tester.tap(find.text('恢复').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏与大字体下撰写栏仍可用', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = DemoMessageRepository();
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
          home: ConversationScreen(repository: repository, hub: hub, thread: thread),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    hub.dispose();
  });
}
