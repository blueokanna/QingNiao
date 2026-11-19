import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_engine.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/compose_screen.dart';
import 'package:qingniao/messaging/conversation_screen.dart';
import 'package:qingniao/messaging/inbox_screen.dart';
import 'package:qingniao/messaging/message_hub.dart';
import 'package:qingniao/messaging/message_widgets.dart';
import 'package:qingniao/messaging/models.dart';
import 'package:qingniao/messaging/sim_identity.dart';

import 'support/fixture_message_repository.dart';

const _cards = [
  SimCard(id: 41, slot: 1, name: 'Personal', carrier: 'Carrier A'),
  SimCard(
    id: 93,
    slot: 2,
    name: 'Travel',
    carrier: 'Carrier B',
    isEmbedded: true,
  ),
  SimCard(id: 0, slot: 0, name: 'Work', isEmbedded: true),
];

class _SimFixture extends FixtureMessageRepository {
  _SimFixture(this.cards);
  List<SimCard> cards;

  @override
  Future<List<SimCard>> subscriptions() async => cards;

  @override
  Future<List<SmsMessage>> messages({
    required int threadId,
    int? before,
    int? beforeDate,
    int limit = 80,
  }) async => [
    SmsMessage(
      id: 801,
      threadId: threadId,
      address: '95588',
      body: 'Personal message',
      date: 1700000000000,
      type: 1,
      read: true,
      subscriptionId: 41,
    ),
    SmsMessage(
      id: 802,
      threadId: threadId,
      address: '95588',
      body: 'Travel message',
      date: 1700000001000,
      type: 1,
      read: true,
      subscriptionId: 93,
    ),
  ];
}

void main() {
  setUpAll(AppStrings.initialize);
  setUp(() => AppStrings.language = 'en');

  test('Subscription IDs resolve to real slots and eSIM names', () {
    expect(MessageSimSource.resolve(41, _cards).label, 'SIM 1 · Personal');
    expect(MessageSimSource.resolve(93, _cards).label, 'eSIM 2 · Travel');
    expect(
      MessageSimSource.resolve(93, _cards).description,
      contains('Subscription ID: 93'),
    );
    expect(MessageSimSource.resolve(0, _cards).label, 'eSIM · Work');
    expect(
      simCardLabel(
        const SimCard(id: 5, slot: -1, name: '', carrier: 'Carrier'),
      ),
      'SIM · Carrier',
    );
  });

  test('Unknown and unavailable subscriptions never impersonate a slot', () {
    expect(MessageSimSource.resolve(-1, _cards).label, 'Unknown SIM');
    expect(MessageSimSource.resolve(-2, _cards).label, 'Unknown SIM');
    expect(MessageSimSource.resolve(7, _cards).label, 'Unavailable SIM · ID 7');
    expect(
      MessageSimSource.resolve(0, const []).label,
      'Unavailable SIM · ID 0',
    );
    expect(
      MessageSimSource.resolve(41, [_cards[1]]).label,
      'Unavailable SIM · ID 41',
    );
  });

  Widget app(
    Widget child,
    AppSettings settings, {
    Brightness brightness = Brightness.light,
    bool large = false,
  }) => AppScope(
    settings: settings,
    child: MaterialApp(
      theme: buildAuroraTheme(
        brightness: brightness,
        appearance: const AuroraAppearance(),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
        child: child!,
      ),
      home: child,
    ),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Incoming and outgoing messages show sources at large text in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = AppSettings()..motionLevel = AuroraMotionLevel.reduced;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final (id, type) in [
                      (41, 1),
                      (93, 2),
                      (-1, 1),
                      (7, 2),
                    ])
                      MessageBubble(
                        sims: _cards,
                        message: SmsMessage(
                          id: id,
                          threadId: 1,
                          address: '123',
                          body: 'Hello',
                          date: 1700000000000,
                          type: type,
                          read: true,
                          subscriptionId: id,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            settings,
            brightness: brightness,
            large: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SimBadge), findsNWidgets(4));
        for (final label in [
          'SIM 1 · Personal',
          'eSIM 2 · Travel',
          'Unknown SIM',
          'Unavailable SIM · ID 7',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );
  }

  testWidgets('Inbox still shows source with a single active SIM', (
    tester,
  ) async {
    final repository = _SimFixture(const [
      SimCard(id: 1, slot: 2, name: 'Personal'),
    ]);
    final hub = MessageHub(repository)..start();
    final settings = AppSettings()..motionLevel = AuroraMotionLevel.reduced;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: InboxScreen(repository: repository, hub: hub),
        ),
        settings,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SIM 2 · Personal'), findsWidgets);
    for (final row in find.byType(ConversationTile).evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(row.widget),
          matching: find.byType(SimBadge),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    hub.dispose();
    settings.dispose();
  });

  testWidgets(
    'Conversation resolves each message and refreshes removed SIM on resume',
    (tester) async {
      final repository = _SimFixture(_cards.take(2).toList());
      final hub = MessageHub(repository);
      final settings = AppSettings()..motionLevel = AuroraMotionLevel.reduced;
      final thread = (await repository.conversations()).first;
      await tester.pumpWidget(
        app(
          ConversationScreen(repository: repository, hub: hub, thread: thread),
          settings,
        ),
      );
      await tester.pumpAndSettle();
      final bubbles = tester
          .widgetList<MessageBubble>(find.byType(MessageBubble))
          .toList();
      expect(bubbles, hasLength(2));
      expect(
        bubbles.every((bubble) => !bubble.groupedTop && !bubble.groupedBottom),
        isTrue,
      );
      expect(find.text('SIM 1 · Personal'), findsOneWidget);
      expect(find.text('eSIM 2 · Travel'), findsOneWidget);
      repository.cards = [_cards[1]];
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(find.text('Unavailable SIM · ID 41'), findsOneWidget);
      expect(find.text('SIM 1 · Personal'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      hub.dispose();
      settings.dispose();
    },
  );

  testWidgets('Composer reflects the selected eSIM', (tester) async {
    final repository = _SimFixture(_cards.take(2).toList());
    final hub = MessageHub(repository);
    final settings = AppSettings()..motionLevel = AuroraMotionLevel.reduced;
    await tester.pumpWidget(
      app(ComposeScreen(repository: repository, hub: hub), settings),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose SIM'));
    await tester.tap(find.text('Choose SIM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('eSIM 2 · Travel'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ActionChip),
        matching: find.text('eSIM 2 · Travel'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    hub.dispose();
    settings.dispose();
  });
}
