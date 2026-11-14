import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppStrings {
  static const languageCodes = ['en', 'zh', 'hi', 'es', 'ar', 'fr', 'bn', 'pt', 'ru', 'ur'];
  static const locales = [Locale('en'), Locale('zh'), Locale('hi'), Locale('es'), Locale('ar'), Locale('fr'), Locale('bn'), Locale('pt'), Locale('ru'), Locale('ur')];
  static final Map<String, Map<String, String>> _catalogs = {};
  static String language = 'en';
  static Future<void> initialize() async {
    for (final code in languageCodes) {
      final data = jsonDecode(await rootBundle.loadString('assets/l10n/$code.json')) as Map;
      _catalogs[code] = data.cast<String, String>();
    }
  }
  static Locale resolve(Locale? requested, Iterable<Locale> supported) {
    language = languageCodes.contains(requested?.languageCode) ? requested!.languageCode : 'en';
    return Locale(language);
  }
  static String text(String source, List<Object?> arguments) {
    final template = _catalogs[language]?[source] ?? source;
    return template.replaceAllMapped(RegExp(r'\{p(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < arguments.length ? '${arguments[index] ?? ''}' : match[0]!;
    });
  }
}

String tr(String source, [List<Object?> arguments = const []]) => AppStrings.text(source, arguments);

class AppStringsDelegate extends LocalizationsDelegate<AppStringsLocale> {
  const AppStringsDelegate();
  @override
  bool isSupported(Locale locale) => AppStrings.languageCodes.contains(locale.languageCode);
  @override
  Future<AppStringsLocale> load(Locale locale) {
    AppStrings.language = locale.languageCode;
    return SynchronousFuture(AppStringsLocale(locale));
  }
  @override
  bool shouldReload(AppStringsDelegate old) => false;
}

class AppStringsLocale {
  const AppStringsLocale(this.locale);
  final Locale locale;
}
