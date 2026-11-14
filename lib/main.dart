import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'app/app_settings.dart';
import 'messaging/demo_repository.dart';
import 'messaging/message_repository.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  const demo = bool.fromEnvironment('QINGNIAO_DEMO');
  final MessageRepository repository = demo ? DemoMessageRepository() : MessageRepository();
  final settings = await AppSettings.load(repository);

  try {
    await RustLib.init();
  } catch (error, stack) {
    debugPrint('Rust 引擎未启用：$error\n$stack');
  }

  runApp(QingniaoApp(repository: repository, settings: settings));
}
