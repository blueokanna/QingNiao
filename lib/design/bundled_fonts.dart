import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class BundledFonts {
  static const families = <String, String?>{
    'system': null,
    'harmony': 'HarmonyOSSans',
    'google': 'GoogleSans',
  };

  static void registerLicenses() {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        'Google Sans',
      ], await rootBundle.loadString('assets/licenses/GoogleSans-OFL.txt'));
      yield LicenseEntryWithLineBreaks(
        ['HarmonyOS Sans'],
        await rootBundle.loadString(
          'assets/licenses/HarmonyOS-Sans-LICENSE.txt',
        ),
      );
    });
  }
}
