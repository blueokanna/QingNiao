import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/conversation_screen.dart';
import 'package:qingniao/messaging/message_hub.dart';
import 'package:qingniao/messaging/message_widgets.dart';
import 'package:qingniao/messaging/models.dart';

import 'support/fixture_message_repository.dart';

class _ConversationRepository extends FixtureMessageRepository {
  final events = StreamController<String>.broadcast(sync: true);
  Completer<void>? gate;
  int reads = 0;
  int activeReads = 0;
  int maxActiveReads = 0;
  int markedRead = 0;
  Completer<Uint8List?>? attachment;
  int attachmentReads = 0;

  @override
  Future<Uint8List?> attachmentData(String uri) {
    attachmentReads++;
    return attachment!.future;
  }

  @override
  Stream<String> get changes => events.stream;

  @override
  Future<List<SmsMessage>> messages({
    required int threadId,
    int? before,
    int? beforeDate,
    int limit = 80,
  }) async {
    reads++;
    activeReads++;
    if (activeReads > maxActiveReads) maxActiveReads = activeReads;
    final pending = gate;
    gate = null;
    await pending?.future;
    activeReads--;
    return [
      SmsMessage(
        id: reads,
        threadId: threadId,
        address: '10086',
        body: 'Incoming message $reads',
        date: DateTime.now().millisecondsSinceEpoch,
        type: 1,
        read: markedRead > 0,
        transport: attachment == null
            ? MessageTransport.sms
            : MessageTransport.mms,
        attachments: attachment == null
            ? const []
            : const [
                Attachment(
                  uri: 'content://mms/part/2',
                  mime: 'image/jpeg',
                  name: 'photo.jpg',
                ),
              ],
      ),
    ];
  }

  @override
  Future<void> markRead(int threadId) async {
    markedRead++;
  }
}

void main() {
  setUpAll(AppStrings.initialize);

  Future<MessageHub> mount(
    WidgetTester tester,
    _ConversationRepository repository,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final hub = MessageHub(repository);
    final settings = AppSettings(repository: repository);
    final thread = (await repository.conversations()).first;
    await tester.pumpWidget(
      AppScope(
        settings: settings,
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
    addTearDown(settings.dispose);
    return hub;
  }

  testWidgets(
    'Repeated preview taps share a read and an unavailable attachment can be retried',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repository = _ConversationRepository()
        ..attachment = Completer<Uint8List?>();
      final hub = await mount(tester, repository);
      await tester.pumpAndSettle();
      final tile = find.byType(AttachmentPreview);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.tap(tile);
      expect(repository.attachmentReads, 1);
      repository.attachment!.completeError(
        StateError('Attachment unavailable'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      repository.attachment = Completer<Uint8List?>()..complete(null);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(repository.attachmentReads, 2);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      hub.dispose();
      await repository.events.close();
    },
  );

  testWidgets(
    'A query finishing in background does not mark incoming SMS read',
    (tester) async {
      final repository = _ConversationRepository();
      final gate = Completer<void>();
      repository.gate = gate;
      final hub = await mount(tester, repository);
      expect(repository.reads, 1);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      gate.complete();
      await tester.pump();
      expect(repository.markedRead, 0);
      repository.events.add('messages');
      await tester.pump(const Duration(milliseconds: 200));
      expect(repository.reads, 1);

      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(repository.reads, 2);
      expect(repository.markedRead, 1);
      expect(find.textContaining('Incoming message 2'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      hub.dispose();
      await repository.events.close();
    },
  );

  testWidgets('Conversation refreshes stay serialized during incoming bursts', (
    tester,
  ) async {
    final repository = _ConversationRepository();
    final hub = await mount(tester, repository);
    final gate = Completer<void>();
    repository.gate = gate;
    for (var i = 0; i < 20; i++) {
      repository.events.add('messages');
    }
    await tester.pump(const Duration(milliseconds: 120));
    expect(repository.reads, 2);
    for (var i = 0; i < 20; i++) {
      repository.events.add('messages');
    }
    await tester.pump(const Duration(milliseconds: 120));
    expect(repository.reads, 2);
    gate.complete();
    await tester.pump();
    expect(repository.reads, 3);
    expect(repository.maxActiveReads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    hub.dispose();
    await repository.events.close();
  });
}
