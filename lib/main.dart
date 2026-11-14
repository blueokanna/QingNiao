import 'package:qingniao/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'app/app_settings.dart';
import 'design/bundled_fonts.dart';
import 'messaging/message_repository.dart';
import 'src/rust/frb_generated.dart';
import 'aurora/aurora_starfield.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStrings.initialize();
  BundledFonts.registerLicenses();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  const repository = MessageRepository();
  final settings = await AppSettings.load(repository);

  try {
    await RustLib.init();
  } catch (error, stack) {
    debugPrint(tr("Rust engine unavailable: {p0}\n{p1}", [error, stack]));
  }

  try {
    await AuroraStarfield.initialize(seed: settings.starfieldSeed);
  } catch (error) {
    debugPrint('Starfield resources unavailable: ${error.runtimeType}');
  }

  runApp(QingniaoApp(repository: repository, settings: settings));
}
