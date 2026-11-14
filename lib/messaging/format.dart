import 'package:qingniao/l10n/app_strings.dart';
import 'dart:math' as math;

abstract final class MessageFormat {
  static final _weekdays = [tr("Monday"), tr("Tuesday"), tr("Wednesday"), tr("Thursday"), tr("Friday"), tr("Saturday"), tr("Sunday")];

  static String time(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  static String inboxTime(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (_sameDay(date, now)) return time(millis);
    final yesterday = now.subtract(const Duration(days: 1));
    if (_sameDay(date, yesterday)) return tr("Yesterday");
    if (date.year == now.year) return tr("{p0}/{p1}", [date.month, date.day]);
    return '${date.year}/${date.month}/${date.day}';
  }

  static String todayLabel() {
    final now = DateTime.now();
    return tr("{p0}/{p1} \u00b7 {p2}", [now.month, now.day, _weekdays[now.weekday - 1]]);
  }

  static String dayLabel(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (_sameDay(date, now)) return tr("Today");
    if (_sameDay(date, now.subtract(const Duration(days: 1)))) return tr("Yesterday");
    if (now.difference(date).inDays < 7) return tr("{p0}", [_weekdays[date.weekday - 1]]);
    if (date.year == now.year) return tr("{p0}/{p1}", [date.month, date.day]);
    return tr("{p0}/{p1}/{p2}", [date.year, date.month, date.day]);
  }

  static String dateTime(int millis) {    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return tr("{p0}/{p1} {p2}", [date.month, date.day, time(millis)]);
  }

  static String fullDate(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return tr("{p0}/{p1}/{p2} {p3}", [date.year, date.month, date.day, time(millis)]);
  }

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

  static String phone(String address) {
    final digits = address.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.length == 13 && digits.startsWith('+86')) {
      final local = digits.substring(3);
      return '${local.substring(0, 3)} ${local.substring(3, 7)} ${local.substring(7)}';
    }
    if (digits.length == 11 && digits.startsWith('1')) {
      return '${digits.substring(0, 3)} ${digits.substring(3, 7)} ${digits.substring(7)}';
    }
    return address;
  }

  static String initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  static String bytes(int value) {
    if (value <= 0) return '0 B';
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(0)} KB';
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static const _gsmExtended = r'^{}\[~]|€';

  static SegmentInfo segment(String body) {
    var gsm = true;
    var septets = 0;
    var utf16 = 0;
    for (final rune in body.runes) {
      utf16 += rune > 0xFFFF ? 2 : 1;
      if (rune > 0x7F && !_gsmExtended.contains(String.fromCharCode(rune))) {
        gsm = false;
      }
      septets += _gsmExtended.codeUnits.contains(rune) ? 2 : 1;
    }
    if (gsm) {
      final per = septets <= 160 ? 160 : 153;
      final segments = septets == 0 ? 1 : (septets / per).ceil();
      return SegmentInfo(
        encoding: 'GSM-7',
        segments: segments,
        length: body.length,
        remaining: segments * per - septets,
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
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11 && digits.startsWith('86')) return digits.substring(2);
    if (digits.length > 11) return digits.substring(digits.length - 11);
    return digits;
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

  String get label => tr("Segments: {p0} \u00b7 {p1} \u00b7 Remaining: {p2}", [segments, encoding, remaining]);
}
