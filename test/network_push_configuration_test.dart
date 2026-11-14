import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/message_repository.dart';
import 'package:qingniao/settings/network_push_screen.dart';

class _PushRepository extends MessageRepository {
  Map<String, dynamic>? saved;
  int enabledCalls = 0;
  static final fixture = {
    'projectId': 'format-test-project',
    'senderId': '123456789012',
    'applicationId': '1:123456789012:android:abcdef1234567890',
    'apiKey': 'AIza${List.filled(35, 'A').join()}',
  };

  @override
  Future<T?> invoke<T>(String method, [MessageRecord? arguments]) async {
    Object? result;
    switch (method) {
      case 'pushStatus':
        result = {
          'configured': saved != null,
          'services': true,
          'enabled': false,
          'configuration': saved,
          'custom': saved != null,
        };
      case 'pickFirebaseConfiguration':
        result = fixture;
      case 'pushSaveConfiguration':
        saved = arguments;
      case 'pushSetEnabled':
        enabledCalls++;
    }
    return result as T?;
  }
}

void main() {
  setUpAll(AppStrings.initialize);
  setUp(() => AppStrings.language = 'en');
  testWidgets(
    'Project import is reviewed and saved without silently enabling push',
    (tester) async {
      final repository = _PushRepository();
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAuroraTheme(
            brightness: Brightness.light,
            appearance: const AuroraAppearance(),
          ),
          home: NetworkPushScreen(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      await tester.ensureVisible(find.text('Save configuration'));
      await tester.tap(find.text('Save configuration'));
      await tester.pumpAndSettle();
      expect(repository.saved, isNull);
      expect(find.text('Check this Firebase field'), findsNWidgets(4));
      await tester.ensureVisible(find.text('Import google-services.json'));
      await tester.tap(find.text('Import google-services.json'));
      await tester.pumpAndSettle();
      expect(repository.saved, isNull);
      await tester.ensureVisible(find.text('Save configuration'));
      await tester.tap(find.text('Save configuration'));
      await tester.pumpAndSettle();
      expect(repository.saved, _PushRepository.fixture);
      expect(repository.enabledCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
