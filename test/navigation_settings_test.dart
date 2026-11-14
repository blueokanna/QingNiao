import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';

import 'support/fixture_message_repository.dart';

void main() {
  test(
    'Installation star seed persists and malformed seeds are repaired',
    () async {
      final repository = FixtureMessageRepository();
      final first = await AppSettings.load(repository);
      final second = await AppSettings.load(repository);
      expect(second.starfieldSeed, first.starfieldSeed);
      await repository.settingsSet('starfieldSeed', '-1');
      final repaired = await AppSettings.load(repository);
      expect(repaired.starfieldSeed, inInclusiveRange(0, 0xffffffff));
      expect(
        (await repository.settingsAll())['starfieldSeed'],
        '${repaired.starfieldSeed}',
      );
      first.dispose();
      second.dispose();
      repaired.dispose();
    },
  );
  test(
    'Navigation customization survives reload and rejects nonfinite data',
    () async {
      final repository = FixtureMessageRepository();
      final settings = AppSettings(repository: repository);
      settings.setNavigationBlur(27);
      settings.setNavigationOpacity(.63);
      final loaded = await AppSettings.load(repository);
      expect(loaded.navigationBlur, 27);
      expect(loaded.navigationOpacity, .63);
      settings.setNavigationBlur(double.nan);
      settings.setNavigationOpacity(double.infinity);
      expect(settings.navigationBlur, 27);
      expect(settings.navigationOpacity, .63);
      await repository.settingsSet('navigationBlur', 'Infinity');
      await repository.settingsSet('navigationOpacity', 'NaN');
      final repaired = await AppSettings.load(repository);
      expect(repaired.navigationBlur, 18);
      expect(repaired.navigationOpacity, .78);
      settings.dispose();
      loaded.dispose();
      repaired.dispose();
    },
  );
}
