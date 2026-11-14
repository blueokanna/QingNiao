import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qingniao/app.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/inbox_screen.dart';
import 'package:qingniao/messaging/models.dart';

import '../test/support/fixture_message_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Profile retained tabs and inbox at the active display cadence', (
    tester,
  ) async {
    await AppStrings.initialize();
    final repository = _CadenceRepository();
    final settings = AppSettings(repository: repository)..localeCode = 'en';
    await tester.pumpWidget(
      QingniaoApp(repository: repository, settings: settings),
    );
    await tester.pump(const Duration(seconds: 2));
    final nav = find.byType(NavigationBar);
    Future<void> select(int index) async {
      final bar = tester.widget<NavigationBar>(nav);
      bar.onDestinationSelected!(index);
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }

    for (final index in [1, 2, 0]) {
      await select(index);
    }
    binding.reportData = {
      'displayRefreshRate': View.of(tester.element(nav)).display.refreshRate,
      'fixture': '164 local test conversations; no Telephony operations',
      'build': 'profile',
    };
    await binding.watchPerformance(() async {
      for (final index in [1, 2, 0, 2, 1, 0, 1, 0, 2, 0, 1, 0]) {
        await select(index);
      }
    }, reportKey: 'tab_transitions');
    await binding.watchPerformance(() async {
      final scroll = find.descendant(
        of: find.byType(InboxScreen),
        matching: find.byType(CustomScrollView),
      );
      for (var i = 0; i < 8; i++) {
        await tester.fling(scroll, Offset(0, i.isEven ? -450 : 450), 1500);
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
    }, reportKey: 'inbox_scroll');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}

class _CadenceRepository extends FixtureMessageRepository {
  @override
  Future<List<ThreadSummary>> conversations({
    String query = '',
    String filter = 'all',
  }) async {
    final seeds = await super.conversations(query: query, filter: filter);
    if (seeds.isEmpty) return [];
    return List.generate(164, (index) {
      final seed = seeds[index % seeds.length];
      return ThreadSummary(
        threadId: index + 1,
        address: '1800000${index.toString().padLeft(4, '0')}',
        displayName: seed.displayName,
        preview: seed.preview,
        date: seed.date - index * 1000,
        unread: seed.unread,
        otp: seed.otp,
        category: seed.category,
        subscriptionId: seed.subscriptionId,
        pinned: index < 2,
        count: seed.count,
      );
    });
  }
}
