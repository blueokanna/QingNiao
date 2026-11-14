import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/design/message_theme.dart';
import 'package:qingniao/messaging/conversation_screen.dart';
import 'package:qingniao/messaging/message_repository.dart';
import 'package:qingniao/messaging/trash_screen.dart';

class WorkflowRepository extends MessageRepository {
  bool failSending = false;
  final operations = <String>[];
  String savedDraft = '';
  @override
  Stream<String> get changes => const Stream.empty();
  @override
  Future<List<MessageRecord>> records(
    String method, [
    MessageRecord? arguments,
  ]) async => switch (method) {
    'subscriptions' => [
      {'id': 1, 'name': 'Test SIM', 'slot': 1},
    ],
    'messages' when arguments?['trash'] == true => [
      {'id': 42, 'address': '10086', 'body': 'Recoverable message'},
    ],
    _ => [],
  };
  @override
  Future<T?> invoke<T>(String method, [MessageRecord? arguments]) async {
    operations.add(method);
    if (method == 'draft') return '' as T;
    if (method == 'saveDraft') savedDraft = arguments!['body'] as String;
    if (method == 'send' && failSending) {
      throw PlatformException(code: 'send_failed', message: '发送失败');
    }
    return null;
  }
}

void main() {
  testWidgets('failed submission preserves editable message and saves draft', (
    tester,
  ) async {
    final repository = WorkflowRepository()..failSending = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: messageTheme(Brightness.light),
        home: ConversationScreen(repository: repository, address: '10086'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Message to preserve');
    await tester.tap(find.byTooltip('发送短信'));
    await tester.pumpAndSettle();
    expect(find.text('Message to preserve'), findsOneWidget);
    expect(find.text('发送失败'), findsOneWidget);
    expect(repository.savedDraft, 'Message to preserve');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('permanent deletion requires an explicit confirmation', (
    tester,
  ) async {
    final repository = WorkflowRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: messageTheme(Brightness.dark),
        home: TrashScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.operations, isNot(contains('delete')));
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(repository.operations, contains('restore'));
  });
  testWidgets(
    'composer remains usable with enlarged text and narrow viewport',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: messageTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.8),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: ConversationScreen(
            repository: WorkflowRepository(),
            address: '10086',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('发送短信'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
