import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_engine.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/inbox_screen.dart';
import 'package:qingniao/messaging/message_hub.dart';
import 'package:qingniao/messaging/message_widgets.dart';

import 'support/fixture_message_repository.dart';

void main() {
  setUpAll(AppStrings.initialize);
  setUp(() => AppStrings.language = 'en');

  Future<(FixtureMessageRepository, MessageHub)> mount(
    WidgetTester tester, {
    AppSettings? settings,
    TextDirection direction = TextDirection.ltr,
  }) async {
    final repository = FixtureMessageRepository();
    final hub = MessageHub(repository)..start();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppScope(
        settings: settings ?? AppSettings(repository: repository),
        child: MaterialApp(
          theme: buildAuroraTheme(
            brightness: Brightness.light,
            appearance: const AuroraAppearance(),
          ),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: InboxScreen(repository: repository, hub: hub),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      hub.dispose();
    });
    return (repository, hub);
  }

  testWidgets(
    'Long press starts selection and taps toggle individual conversations',
    (tester) async {
      await mount(tester);
      final rows = find.byType(ConversationTile);
      await tester.longPress(rows.first);
      await tester.pump();
      expect(find.text('Selected: 1'), findsOneWidget);
      await tester.tap(rows.at(1));
      await tester.pump();
      expect(find.text('Selected: 2'), findsOneWidget);
      await tester.tap(rows.first);
      await tester.pump();
      expect(find.text('Selected: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Mark all read updates every conversation in storage', (
    tester,
  ) async {
    final (repository, _) = await mount(tester);
    expect((await repository.conversations()).any((t) => t.unread > 0), isTrue);
    await tester.tap(find.byTooltip('Mark all as read'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      (await repository.conversations()).every((t) => t.unread == 0),
      isTrue,
    );
  });

  for (final direction in TextDirection.values) {
    testWidgets('Physical left swipe moves to trash in $direction', (
      tester,
    ) async {
      final (repository, _) = await mount(tester, direction: direction);
      final before = (await repository.trash()).length;
      await tester.drag(
        find.byType(ConversationTile).first,
        const Offset(-300, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect((await repository.trash()).length, greaterThan(before));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Canceled swipe and disabled gestures do not change storage', (
    tester,
  ) async {
    final settings = AppSettings()..swipeLeft = ThreadSwipeAction.none;
    final (repository, _) = await mount(tester, settings: settings);
    final before = (await repository.trash()).length;
    await tester.drag(
      find.byType(ConversationTile).first,
      const Offset(-280, 0),
    );
    await tester.pump(const Duration(seconds: 1));
    expect((await repository.trash()).length, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Batch copy uses selected conversations and clears selection', (
    tester,
  ) async {
    final (repository, hub) = await mount(tester);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final expected = await repository.copyThreads([hub.threads.first.threadId]);
    await tester.longPress(find.byType(ConversationTile).first);
    await tester.pump();
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy text'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(clipboard, expected);
    expect(find.text('Selected: 1'), findsNothing);
  });

  testWidgets(
    'Ambient clock caps decorative updates at 30 Hz and stops when paused',
    (tester) async {
      final engine = AuroraEngine.instance;
      engine.setRefreshRate(120);
      engine.configure(
        motion: AuroraMotionLevel.full,
        reduce: false,
        backdrop: true,
      );
      engine.attach(tester);
      var frames = 0;
      void count() => frames++;
      engine.clock.addListener(count);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(microseconds: 8333));
      }
      expect(frames, inInclusiveRange(4, 5));
      final beforePause = frames;
      engine.pause();
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames, beforePause);
      engine.clock.removeListener(count);
      engine.detach();
      engine.resume();
    },
  );
}
