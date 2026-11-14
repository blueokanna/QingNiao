import 'dart:math' as math;

abstract final class MessageFormat {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static String time(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  static String inboxTime(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (_sameDay(date, now)) return time(millis);
    final yesterday = now.subtract(const Duration(days: 1));
    if (_sameDay(date, yesterday)) return '昨天';
    if (date.year == now.year) return '${date.month}月${date.day}日';
    return '${date.year}/${date.month}/${date.day}';
  }

  static String todayLabel() {
    final now = DateTime.now();
    return '${now.month} 月 ${now.day} 日 · 周${_weekdays[now.weekday - 1]}';
  }

  static String dayLabel(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (_sameDay(date, now)) return '今天';
    if (_sameDay(date, now.subtract(const Duration(days: 1)))) return '昨天';
    if (now.difference(date).inDays < 7) return '周${_weekdays[date.weekday - 1]}';
    if (date.year == now.year) return '${date.month}月${date.day}日';
    return '${date.year}年${date.month}月${date.day}日';
  }

  static String dateTime(int millis) {    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${date.month}月${date.day}日 ${time(millis)}';
  }

  static String fullDate(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${date.year}年${date.month}月${date.day}日 ${time(millis)}';
  }

  static String duration(int millis) {
    if (millis < 1000) return '刚刚';
    final seconds = millis ~/ 1000;
    if (seconds < 60) return '$seconds 秒前';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分钟前';
    final hours = minutes ~/ 60;
    if (hours < 24) return '$hours 小时前';
    return '${hours ~/ 24} 天前';
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

  String get label => '$segments 条 · $encoding · 余 $remaining 字';
}
