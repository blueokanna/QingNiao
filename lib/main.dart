import 'package:flutter/material.dart';

import 'design/message_theme.dart';
import 'messaging/inbox_screen.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RustLib.init();
    runApp(const QingniaoApp());
  } catch (_) {
    runApp(
      MaterialApp(
        theme: messageTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('本地消息引擎未能启动'),
                const SizedBox(height: 16),
                FilledButton(onPressed: main, child: const Text('重试')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QingniaoApp extends StatelessWidget {
  const QingniaoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '青鸟短信',
    debugShowCheckedModeBanner: false,
    theme: messageTheme(Brightness.light),
    darkTheme: messageTheme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: const InboxScreen(),
  );
}
