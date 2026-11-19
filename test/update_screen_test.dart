import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/message_repository.dart';
import 'package:qingniao/updates/update_controller.dart';
import 'package:qingniao/updates/update_screen.dart';

class _UpdateScreenRepository extends MessageRepository {
  String phase = 'available';
  String? error;
  final calls = <String>[];

  @override
  Future<T?> invoke<T>(String method, [MessageRecord? arguments]) async {
    calls.add(method);
    if (method == 'openUpdateInstallSettings') return null;
    return <dynamic, dynamic>{
      'versionName': '0.1.1',
      'versionCode': 1,
      'phase': phase,
      'canInstall': false,
      'error': error,
      'received': 4096,
      'release': {
        'versionName': '0.1.2',
        'versionCode': 2,
        'size': 8192,
        'pageUrl': 'https://github.com/blueokanna/qingniao/releases/tag/v0.1.2',
        'notes': 'Bug fixes and interface refinements.',
      },
    } as T;
  }
}

void main() {
  setUpAll(AppStrings.initialize);
  for (final language in ['zh', 'en', 'ar']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Update flow remains usable in $language ${brightness.name} with large text',
        (tester) async {
          AppStrings.language = language;
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repository = _UpdateScreenRepository();
          final controller = UpdateController(repository);
          await controller.refresh();
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAuroraTheme(
                brightness: brightness,
                appearance: const AuroraAppearance(),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: Directionality(
                  textDirection: language == 'ar'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: child!,
                ),
              ),
              home: UpdateScreen(controller: controller),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(tr('Update available: {p0}', ['0.1.2'])),
            findsOneWidget,
          );
          final download = find.text(tr('Download update'));
          await tester.ensureVisible(download);
          await tester.pumpAndSettle();
          await tester.tap(download);
          await tester.pump();
          expect(repository.calls, contains('downloadUpdate'));
          repository.phase = 'ready';
          await controller.refresh();
          await tester.pumpAndSettle();
          final install = find.text(tr('Allow app installation'));
          await tester.ensureVisible(install);
          await tester.pumpAndSettle();
          await tester.tap(install);
          expect(repository.calls.last, 'openUpdateInstallSettings');
          repository.phase = 'error';
          repository.error = 'download_failed';
          await controller.refresh();
          await tester.pumpAndSettle();
          expect(
            find.text(
              tr(
                'Download or verification failed. Check your connection and retry.',
              ),
            ),
            findsOneWidget,
          );
          expect(find.text(tr('Download update')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        },
      );
    }
  }
}
