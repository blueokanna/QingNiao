import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/aurora/aurora_widgets.dart';
import 'package:qingniao/messaging/message_hub.dart';

import 'support/fixture_message_repository.dart';

void main() {
  test(
    'Unread badges remain global and OTP read leaves other messages unread',
    () async {
      final repository = FixtureMessageRepository();
      final hub = MessageHub(repository);
      addTearDown(hub.dispose);
      await hub.refresh();
      final initialUnread = hub.unread;
      final initialCodes = hub.otpCount;
      expect(initialUnread, greaterThan(0));
      expect(hub.otpUnread, greaterThan(0));
      hub.filter = 'pinned';
      await hub.refresh();
      expect(hub.unread, initialUnread);
      expect(hub.otpCount, initialCodes);
      await hub.markAllRead(verificationOnly: true);
      expect(hub.otpUnread, 0);
      expect(hub.otpCount, initialCodes);
      expect(hub.unread, greaterThan(0));
      await hub.markAllRead();
      expect(hub.unread, 0);
      expect(hub.otpUnread, 0);
    },
  );

  testWidgets(
    'Whole navigation destination supports long press without switching',
    (tester) async {
      var reads = 0;
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAuroraTheme(
            brightness: Brightness.light,
            appearance: const AuroraAppearance(),
          ),
          home: Scaffold(
            bottomNavigationBar: AuroraNavBar(
              index: 0,
              onSelected: (value) => selected = value,
              destinations: [
                const AuroraNavDestination(
                  icon: Icons.forum,
                  selectedIcon: Icons.forum,
                  label: 'Messages',
                ),
                AuroraNavDestination(
                  icon: Icons.shield,
                  selectedIcon: Icons.shield,
                  label: 'Codes',
                  onLongPress: () => reads++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Codes'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(selected, 0);
      await tester.tap(find.text('Codes'));
      expect(selected, 1);
    },
  );
}
