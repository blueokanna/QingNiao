import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/messaging/message_repository.dart';
import 'package:qingniao/updates/update_controller.dart';

class _UpdateRepository extends MessageRepository {
  bool automatic = true;
  final calls = <String>[];
  Map<String, dynamic> state = {
    'versionName': '0.1.1',
    'versionCode': 1,
    'phase': 'idle',
    'lastChecked': 0,
    'canInstall': false,
  };
  bool invalidInstall = false;

  @override
  Future<Map<String, String>> settingsAll() async => {
    'automaticUpdates': '$automatic',
  };
  @override
  Future<void> settingsSet(String key, String value) async {
    if (key == 'automaticUpdates') automatic = value == 'true';
  }

  @override
  Future<T?> invoke<T>(String method, [MessageRecord? arguments]) async {
    calls.add(method);
    if (method == 'checkForUpdate') {
      state = {
        ...state,
        'phase': 'current',
        'lastChecked': DateTime.now().millisecondsSinceEpoch,
      };
    }
    if (method == 'installUpdate' && invalidInstall) {
      state = {...state, 'phase': 'error', 'error': 'download_failed'};
      throw PlatformException(code: 'invalid_update');
    }
    if (method == 'openUpdateInstallSettings' || method == 'installUpdate') {
      return null;
    }
    return Map<dynamic, dynamic>.from(state) as T;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'startup checks once and foreground resumes respect the interval',
    (tester) async {
      final repository = _UpdateRepository();
      final controller = UpdateController(repository);
      await controller.start();
      expect(
        repository.calls.where((call) => call == 'checkForUpdate'),
        hasLength(1),
      );
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await controller.checkAutomatically();
      expect(
        repository.calls.where((call) => call == 'checkForUpdate'),
        hasLength(1),
      );
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        repository.calls.where((call) => call == 'checkForUpdate'),
        hasLength(1),
      );
      controller.dispose();
    },
  );

  testWidgets(
    'foreground timer checks again and a background interval stays idle',
    (tester) async {
      final repository = _UpdateRepository();
      final controller = UpdateController(repository);
      await controller.start();
      await tester.pump(UpdateController.checkInterval);
      expect(
        repository.calls.where((call) => call == 'checkForUpdate'),
        hasLength(2),
      );
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(UpdateController.checkInterval);
      expect(
        repository.calls.where((call) => call == 'checkForUpdate'),
        hasLength(2),
      );
      controller.dispose();
    },
  );

  testWidgets('disabled automatic updates still allow an explicit check', (
    tester,
  ) async {
    final repository = _UpdateRepository()..automatic = false;
    final controller = UpdateController(repository);
    await controller.start();
    expect(repository.calls, ['updateInfo']);
    await controller.check();
    expect(repository.calls.last, 'checkForUpdate');
    controller.dispose();
  });

  testWidgets(
    'background suspends download polling and resume catches completion',
    (tester) async {
      final repository = _UpdateRepository()..automatic = false;
      repository.state['phase'] = 'downloading';
      final controller = UpdateController(repository);
      await controller.start();
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      final before = repository.calls.length;
      await tester.pump(const Duration(seconds: 5));
      expect(repository.calls.length, before);
      repository.state['phase'] = 'ready';
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(controller.phase, 'ready');
      controller.dispose();
    },
  );

  testWidgets(
    'installation requests permission first and invalid files become retryable',
    (tester) async {
      final repository = _UpdateRepository()..automatic = false;
      final controller = UpdateController(repository);
      await controller.start();
      await controller.install();
      expect(repository.calls.last, 'openUpdateInstallSettings');
      repository.state.addAll({'phase': 'ready', 'canInstall': true});
      repository.invalidInstall = true;
      await controller.refresh();
      await controller.install();
      expect(controller.phase, 'error');
      expect(controller.error, 'download_failed');
      controller.dispose();
    },
  );
}
