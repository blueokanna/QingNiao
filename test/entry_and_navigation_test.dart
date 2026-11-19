import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_engine.dart';
import 'package:qingniao/aurora/aurora_tab_transition.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/models.dart';
import 'package:qingniao/messaging/compose_screen.dart';

import 'support/fixture_message_repository.dart';

class _PermissionFixture extends FixtureMessageRepository {
  @override
  Future<AccessState> access() async => const AccessState();
}

void main() {
  setUpAll(AppStrings.initialize);
  testWidgets(
    'First launch opens the inbox with only the required access action',
    (tester) async {
      final settings = AppSettings()
        ..localeCode = 'en'
        ..motionLevel = AuroraMotionLevel.reduced;
      await tester.pumpWidget(
        QingniaoApp(repository: _PermissionFixture(), settings: settings),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Set as default SMS app'), findsOneWidget);
      expect(find.text('Material 3 Expressive'), findsNothing);
      expect(find.text('Make room for\nwhat matters.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets('Compose entry shows an icon and label and opens the editor', (
    tester,
  ) async {
    final settings = AppSettings()
      ..localeCode = 'en'
      ..motionLevel = AuroraMotionLevel.reduced;
    await tester.pumpWidget(
      QingniaoApp(repository: FixtureMessageRepository(), settings: settings),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final button = find.byType(FloatingActionButton);
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('Compose')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: button, matching: find.byIcon(Icons.edit_rounded)),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(ComposeScreen), findsOneWidget);
    expect(find.text('New message'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets(
    'Direct tab transitions preserve text and skip unvisited intermediate pages',
    (tester) async {
      final engine = AuroraEngine.instance;
      engine.configure(
        motion: AuroraMotionLevel.full,
        reduce: false,
        backdrop: false,
      );
      engine.attach(tester);
      var index = 0;
      late StateSetter update;
      final input = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: AuroraTabTransition(
                  index: index,
                  children: [
                    TextField(controller: input),
                    const Text('Intermediate page'),
                    const Text('Settings page'),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Retained search');
      update(() => index = 2);
      await tester.pumpAndSettle();
      expect(find.text('Settings page'), findsOneWidget);
      expect(find.text('Intermediate page'), findsNothing);
      update(() => index = 0);
      await tester.pump(const Duration(milliseconds: 32));
      update(() => index = 2);
      await tester.pump(const Duration(milliseconds: 16));
      update(() => index = 0);
      await tester.pumpAndSettle();
      expect(find.text('Retained search'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      input.dispose();
      engine.detach();
    },
  );
}
