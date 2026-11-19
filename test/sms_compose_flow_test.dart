import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_engine.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/compose_screen.dart';
import 'package:qingniao/messaging/conversation_screen.dart';
import 'package:qingniao/messaging/models.dart';

import 'support/fixture_message_repository.dart';

class _SmsRepository extends FixtureMessageRepository {
  final events = StreamController<String>.broadcast();
  Map<String, dynamic> intent = {};
  final sent = <({String address, String body})>[];
  bool failSend = false;
  bool ready = true;
  int contactsPicked = 0;
  String? scheduledAddress;
  Completer<void>? draftGate;

  @override
  Stream<String> get changes => events.stream;

  @override
  Future<AccessState> access() async =>
      ready ? super.access() : const AccessState();

  @override
  Future<Map<String, dynamic>> launchIntent() async {
    final next = intent;
    intent = {};
    return next;
  }

  @override
  Future<int?> send({
    required String address,
    required String body,
    int? subscriptionId,
  }) async {
    if (failSend) {
      throw PlatformException(code: 'failed', message: 'No service');
    }
    sent.add((address: address, body: body));
    return 123;
  }

  @override
  Future<ContactChoice?> pickContact() async {
    contactsPicked++;
    return super.pickContact();
  }

  @override
  Future<int> schedule({
    required String address,
    required String body,
    required int at,
    int? subscriptionId,
  }) async {
    scheduledAddress = address;
    return 1;
  }

  @override
  Future<void> saveDraft(String address, String body) async {
    await draftGate?.future;
    return super.saveDraft(address, body);
  }
}

void main() {
  setUpAll(AppStrings.initialize);
  setUp(() => AppStrings.language = 'en');

  Future<void> mount(WidgetTester tester, _SmsRepository repository) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final settings = AppSettings()
      ..localeCode = 'en'
      ..motionLevel = AuroraMotionLevel.reduced;
    await tester.pumpWidget(
      QingniaoApp(repository: repository, settings: settings),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      await repository.events.close();
    });
  }

  Finder editor(String hint) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hint,
  );

  testWidgets('Typed unsaved number sends without submitting phone keyboard', (
    tester,
  ) async {
    final repository = _SmsRepository();
    await mount(tester, repository);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(editor('Number'), '+86 13800138000');
    await tester.enterText(editor('Write a message…'), 'Hello unsaved number');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(repository.sent, [
      (address: '+86 13800138000', body: 'Hello unsaved number'),
    ]);
    expect(repository.contactsPicked, 0);
    expect(find.byType(ComposeScreen), findsNothing);
  });

  testWidgets('Failed submission retains body and allows retry', (
    tester,
  ) async {
    final repository = _SmsRepository()..failSend = true;
    await mount(tester, repository);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(editor('Number'), '10086');
    await tester.enterText(editor('Write a message…'), 'Retry this');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('No service'), findsOneWidget);
    expect(find.text('Retry this'), findsOneWidget);
    repository.failSend = false;
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(repository.sent.single, (address: '10086', body: 'Retry this'));
  });

  testWidgets(
    'Scheduling commits a typed number before opening the date picker',
    (tester) async {
      final repository = _SmsRepository();
      await mount(tester, repository);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(editor('Number'), '10086');
      await tester.enterText(editor('Write a message…'), 'Later');
      await tester.tap(find.byTooltip('Schedule message'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Cold launch preserves body even when the recipient has a thread',
    (tester) async {
      final repository = _SmsRepository();
      final address = (await repository.conversations()).first.address;
      repository.intent = {
        'compose': true,
        'recipients': [address],
        'address': address,
        'body': 'External message\nSecond line',
      };
      await mount(tester, repository);
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(find.byType(ConversationScreen), findsNothing);
      expect(find.text('External message\nSecond line'), findsOneWidget);
      expect(find.text(address), findsOneWidget);
      expect(repository.sent, isEmpty);
    },
  );

  testWidgets('Body-only request survives missing SMS permissions', (
    tester,
  ) async {
    final repository = _SmsRepository()
      ..ready = false
      ..intent = {
        'compose': true,
        'recipients': <String>[],
        'body': 'Shared text',
      };
    await mount(tester, repository);
    expect(find.byType(ComposeScreen), findsOneWidget);
    expect(find.text('Shared text'), findsOneWidget);
    expect(repository.sent, isEmpty);
  });

  testWidgets('Warm launch opens and prefills a fresh composer once', (
    tester,
  ) async {
    final repository = _SmsRepository();
    await mount(tester, repository);
    repository.intent = {
      'compose': true,
      'recipients': ['12345', '+8613800138000'],
      'body': 'Warm launch',
    };
    repository.events.add('intent');
    await tester.pumpAndSettle();
    expect(find.byType(ComposeScreen), findsOneWidget);
    expect(find.text('12345'), findsOneWidget);
    expect(find.text('+8613800138000'), findsOneWidget);
    expect(find.text('Warm launch'), findsOneWidget);
    repository.events.add('intent');
    await tester.pumpAndSettle();
    expect(find.byType(ComposeScreen, skipOffstage: false), findsOneWidget);
    expect(repository.sent, isEmpty);
  });

  testWidgets('Empty external compose request still opens the editor', (
    tester,
  ) async {
    final repository = _SmsRepository()
      ..intent = {'compose': true, 'recipients': <String>[], 'body': ''};
    await mount(tester, repository);
    expect(find.byType(ComposeScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(editor('Number')).controller!.text,
      isEmpty,
    );
  });

  testWidgets('A new external request opens above an existing composer', (
    tester,
  ) async {
    final repository = _SmsRepository();
    await mount(tester, repository);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(editor('Write a message…'), 'Original draft');
    repository.intent = {
      'compose': true,
      'recipients': ['12345'],
      'body': 'New external request',
    };
    repository.events.add('intent');
    await tester.pumpAndSettle();
    expect(find.text('New external request'), findsOneWidget);
    expect(find.byType(ComposeScreen, skipOffstage: false), findsNWidgets(2));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Original draft'), findsOneWidget);
  });

  testWidgets(
    'Conversation editor unlocks while post-send draft work is blocked',
    (tester) async {
      final repository = _SmsRepository();
      final address = (await repository.conversations()).first.address;
      repository.intent = {'address': address};
      await mount(tester, repository);
      expect(find.byType(ConversationScreen), findsOneWidget);
      repository.draftGate = Completer<void>();
      await tester.enterText(editor('Write a message…'), 'First message');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(repository.sent.length, 1);
      expect(
        tester.widget<TextField>(editor('Write a message…')).enabled,
        isTrue,
      );
      await tester.enterText(editor('Write a message…'), 'Second message');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(repository.sent.length, 2);
      repository.draftGate!.complete();
      await tester.pumpAndSettle();
    },
  );
}
