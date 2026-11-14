import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/app/app_settings.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/l10n/app_strings.dart';
import 'package:qingniao/messaging/format.dart';
import 'package:qingniao/messaging/inbox_screen.dart';
import 'package:qingniao/messaging/otp_screen.dart';
import 'package:qingniao/messaging/message_hub.dart';
import 'package:qingniao/settings/appearance_screen.dart';

import 'support/fixture_message_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppStrings.initialize);
  for (final code in AppStrings.languageCodes) {
    for (final page in [0, 1, 2]) {
      final appearance = page == 1;
      final otp = page == 2;
      testWidgets(
        '${appearance
            ? "Appearance"
            : otp
            ? "OTP"
            : "Inbox"} supports $code direction and large text',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repository = FixtureMessageRepository();
          final hub = MessageHub(repository)..start();
          await tester.pumpWidget(
            AppScope(
              settings: AppSettings(repository: repository),
              child: MaterialApp(
                locale: Locale(code),
                supportedLocales: AppStrings.locales,
                localizationsDelegates: const [
                  AppStringsDelegate(),
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: buildAuroraTheme(
                  brightness: Brightness.light,
                  appearance: const AuroraAppearance(),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: child!,
                ),
                home: Scaffold(
                  body: appearance
                      ? const AppearanceScreen()
                      : otp
                      ? OtpScreen(repository: repository, hub: hub)
                      : InboxScreen(repository: repository, hub: hub),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          expect(
            Directionality.of(
              tester.element(
                find.byType(
                  appearance
                      ? AppearanceScreen
                      : otp
                      ? OtpScreen
                      : InboxScreen,
                ),
              ),
            ),
            ['ar', 'ur'].contains(code) ? TextDirection.rtl : TextDirection.ltr,
          );
          expect(
            find.text(
              tr(
                appearance
                    ? 'Appearance'
                    : otp
                    ? 'Verification codes'
                    : 'Messages',
              ),
            ),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
          hub.dispose();
        },
      );
    }
  }
  test('Catalog placeholders preserve parameter identity', () async {
    final pattern = RegExp(r'\{p\d+\}');
    for (final code in AppStrings.languageCodes) {
      final catalog = jsonDecode(
        await rootBundle.loadString('assets/l10n/$code.json'),
      ) as Map;
      for (final entry in catalog.entries) {
        expect(
          pattern.allMatches(entry.value as String).map((m) => m[0]).toSet(),
          pattern.allMatches(entry.key as String).map((m) => m[0]).toSet(),
          reason: '$code: ${entry.key}',
        );
      }
    }
  });
  test('International phone identities do not collapse to a local suffix', () {
    expect(MessageFormat.normalizeNumber('+1 234 567 8901'), '+12345678901');
    expect(MessageFormat.normalizeNumber('+86 234 567 8901'), '+862345678901');
    expect(MessageFormat.normalizeNumber('0044 20 7946 0000'), '+442079460000');
  });
  test('SMS estimates preserve accented GSM text and segment boundaries', () {
    expect(MessageFormat.segment('é' * 160).segments, 1);
    expect(MessageFormat.segment('€' * 80).remaining, 0);
    expect(MessageFormat.segment('a' * 306).remaining, 0);
    expect(MessageFormat.segment('`').encoding, 'UCS-2');
    expect(MessageFormat.segment('').segments, 0);
    expect(MessageFormat.initials('👩🏽‍💻 team'), '👩🏽‍💻');
  });
  test('Locale resolution considers the full system preference list', () {
    expect(
      AppStrings.resolve([
        const Locale('ja'),
        const Locale('fr'),
      ], AppStrings.locales),
      const Locale('fr'),
    );
    expect(
      AppStrings.resolve([const Locale('ja')], AppStrings.locales),
      const Locale('en'),
    );
  });
  test(
    'Reference primaries match the supplied PDF conversion and readable text',
    () async {
      final reference = jsonDecode(
        await rootBundle.loadString('assets/palettes/coated_reference.json'),
      ) as Map;
      for (final swatch in reference['swatches'] as List) {
        final color = Color(
          int.parse('FF${(swatch['hex'] as String).substring(1)}', radix: 16),
        );
        expect(AuroraPalettes.seeds[swatch['label']], color);
        for (final brightness in Brightness.values) {
          final scheme = buildAuroraTheme(
            brightness: brightness,
            appearance: AuroraAppearance(seed: color, useDynamic: false),
          ).colorScheme;
          expect(scheme.primary, color);
          final a = scheme.primary.computeLuminance();
          final b = scheme.onPrimary.computeLuminance();
          final contrast = a > b
              ? (a + .05) / (b + .05)
              : (b + .05) / (a + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
        }
      }
    },
  );
}
