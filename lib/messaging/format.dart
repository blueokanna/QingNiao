import 'package:qingniao/l10n/app_strings.dart';

import 'dart:math' as math;

import 'package:characters/characters.dart';

import 'package:intl/intl.dart';

abstract final class MessageFormat {
  static String time(int millis) =>
      DateFormat.jm(AppStrings.language)
          .format(DateTime.fromMillisecondsSinceEpoch(millis));
  static String inboxTime(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (_sameDay(date, now)) return time(millis);
    if (_sameDay(date, DateTime(now.year, now.month, now.day - 1))) {
      return tr('Yesterday');
    }
    return (date.year == now.year
            ? DateFormat.MMMd(AppStrings.language)
            : DateFormat.yMMMd(AppStrings.language))
        .format(date);
  }

  static String todayLabel() =>
      DateFormat.MMMEd(AppStrings.language).format(DateTime.now());
  static String dayLabel(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (_sameDay(date, now)) return tr('Today');
    if (_sameDay(date, DateTime(now.year, now.month, now.day - 1))) {
      return tr('Yesterday');
    }
    return DateFormat.yMMMd(AppStrings.language).format(date);
  }

  static String dateTime(int millis) =>
      DateFormat.MMMd(AppStrings.language)
          .add_jm()
          .format(DateTime.fromMillisecondsSinceEpoch(millis));
  static String fullDate(int millis) =>
      DateFormat.yMMMd(AppStrings.language)
          .add_jm()
          .format(DateTime.fromMillisecondsSinceEpoch(millis));

  static String duration(int millis) {
    if (millis < 1000) return tr("Just now");
    final seconds = millis ~/ 1000;
    if (seconds < 60) return tr("Seconds ago: {p0}", [seconds]);
    final minutes = seconds ~/ 60;
    if (minutes < 60) return tr("Minutes ago: {p0}", [minutes]);
    final hours = minutes ~/ 60;
    if (hours < 24) return tr("Hours ago: {p0}", [hours]);
    return tr("Days ago: {p0}", [hours ~/ 24]);
  }

  static String phone(String address) => address;

  static String initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  static String bytes(int value) {
    if (value <= 0) return '0 B';
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(0)} KB';
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static const _gsmExtended = '^{}\\[~]|€\f';
  static const _gsmAccents = '¤£¥èéùìòÇØøÅåΔΦΓΛΩΠΨΣΘΞÆæßÉ¡ÄÖÑÜ§¿äöñüà';

  static SegmentInfo segment(String body) {
    var gsm = true;
    var septets = 0;
    var utf16 = 0;
    for (final rune in body.runes) {
      utf16 += rune > 0xFFFF ? 2 : 1;
      final character = String.fromCharCode(rune);
      final extended = _gsmExtended.contains(character);
      final basic =
          rune == 10 ||
          rune == 13 ||
          (rune >= 32 && rune <= 126 && rune != 96) ||
          _gsmAccents.contains(character);
      if (!basic && !extended) {
        gsm = false;
      }
      septets += extended ? 2 : 1;
    }
    if (gsm) {
      final per = septets <= 160 ? 160 : 153;
      final segments = (septets / per).ceil();
      return SegmentInfo(
        encoding: 'GSM-7',
        segments: segments,
        length: body.length,
        remaining: segments == 0 ? per : segments * per - septets,
        perSegment: per,
      );
    }
    final per = utf16 <= 70 ? 70 : 67;
    final segments = utf16 == 0 ? 1 : (utf16 / per).ceil();
    return SegmentInfo(
      encoding: 'UCS-2',
      segments: segments,
      length: body.length,
      remaining: segments * per - utf16,
      perSegment: per,
    );
  }

  static String truncate(String value, int max) {
    if (value.runes.length <= max) return value;
    return '${String.fromCharCodes(value.runes.take(max))}…';
  }

  static String normalizeNumber(String value) {
    final number = value.replaceAll(RegExp(r'[^0-9+]'), '');
    return number.startsWith('00') ? '+${number.substring(2)}' : number;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int stableHash(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  static double clamp01(double value) => math.min(1, math.max(0, value));
}

class SegmentInfo {
  const SegmentInfo({
    required this.encoding,
    required this.segments,
    required this.length,
    required this.remaining,
    required this.perSegment,
  });

  final String encoding;
  final int segments;
  final int length;
  final int remaining;
  final int perSegment;

  String get label => tr("Segments: {p0} \u00b7 {p1} \u00b7 Remaining: {p2}", [
    segments,
    encoding,
    remaining,
  ]);
}
