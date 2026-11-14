import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

abstract final class AppStrings {
  static const languageCodes = [
    'en',
    'zh',
    'hi',
    'es',
    'ar',
    'fr',
    'bn',
    'pt',
    'ru',
    'ur',
  ];
  static const locales = [
    Locale('en'),
    Locale('zh'),
    Locale('hi'),
    Locale('es'),
    Locale('ar'),
    Locale('fr'),
    Locale('bn'),
    Locale('pt'),
    Locale('ru'),
    Locale('ur'),
  ];
  static final Map<String, Map<String, String>> _catalogs = {};
  static String language = 'en';
  static const languageNames = {
    'en': 'English',
    'zh': '\u4e2d\u6587',
    'hi': 'हिन्दी',
    'es': 'Español',
    'ar': 'العربية',
    'fr': 'Français',
    'bn': 'বাংলা',
    'pt': 'Português',
    'ru': 'Русский',
    'ur': 'اردو',
  };
  static Future<void> initialize() async {
    await initializeDateFormatting();
    for (final code in languageCodes) {
      final data = jsonDecode(
        await rootBundle.loadString('assets/l10n/$code.json'),
      ) as Map;
      _catalogs[code] = data.cast<String, String>();
    }
  }

  static Locale resolve(List<Locale>? requested, Iterable<Locale> supported) {
    language =
        (requested ?? const <Locale>[])
            .map((locale) => locale.languageCode)
            .where(languageCodes.contains)
            .firstOrNull ??
        'en';
    return Locale(language);
  }

  static String? paletteKey(String? saved) {
    if (saved == null || saved.startsWith('PANTONE ')) return saved;
    for (final entry in (_catalogs['zh'] ?? <String, String>{}).entries) {
      if (entry.key.startsWith('PANTONE ') && entry.value == saved) {
        return entry.key;
      }
    }
    return saved;
  }

  static String text(String source, List<Object?> arguments) {
    final template = _catalogs[language]?[source] ?? source;
    return template.replaceAllMapped(RegExp(r'\{p(\d+)\}'), (match) {
      final index = int.parse(match[1]!);
      return index < arguments.length ? '${arguments[index] ?? ''}' : match[0]!;
    });
  }
}

String tr(String source, [List<Object?> arguments = const []]) =>
    AppStrings.text(source, arguments);

class AppStringsDelegate extends LocalizationsDelegate<AppStringsLocale> {
  const AppStringsDelegate();
  @override
  bool isSupported(Locale locale) =>
      AppStrings.languageCodes.contains(locale.languageCode);
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
