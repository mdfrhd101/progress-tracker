import 'package:intl/intl.dart';

/// Duration / date formatting helpers used across the tracker and analytics.
class Formatters {
  Formatters._();

  /// Seconds → "HH:MM:SS" (zero-padded, hours grow unbounded).
  static String hms(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(sec)}';
  }

  /// Seconds → human summary, e.g. "3h 45m", "45m", "0m".
  static String human(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  /// Epoch ms → "08:05 AM".
  static String clock(int epochMs) =>
      DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(epochMs));

  /// Two epoch-ms timestamps → "08:00 AM - 09:30 AM".
  static String timeRange(int startMs, int endMs) =>
      '${clock(startMs)} - ${clock(endMs)}';

  /// Epoch ms → "Sep 5, 2026".
  static String longDate(int epochMs) => DateFormat('MMM d, yyyy')
      .format(DateTime.fromMillisecondsSinceEpoch(epochMs));

  /// "YYYY-MM-DD" → short weekday label for the chart, e.g. "Fri".
  static String weekdayShort(String dateString) {
    final parts = dateString.split('-');
    final d = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    return DateFormat('EEE').format(d); // Mon, Tue, ...
  }
}
