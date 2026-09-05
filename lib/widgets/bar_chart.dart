import 'package:flutter/material.dart';

import '../data/models/session.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// A dependency-free vertical bar chart of focus time for the last 7 days.
/// Drawn entirely with a [CustomPainter] (no charting package).
class SevenDayBarChart extends StatelessWidget {
  final List<DailyTotal> data; // oldest → newest, exactly 7 entries expected

  const SevenDayBarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarChartPainter(data),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<DailyTotal> data;
  _BarChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const double labelZone = 22; // space for weekday labels
    const double valueZone = 16; // space above bars for hour value
    final double chartH = size.height - labelZone - valueZone;
    final double slot = size.width / data.length;
    final double barW = slot * 0.5;

    final maxSeconds = data
        .map((d) => d.totalActiveSeconds)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final safeMax = maxSeconds == 0 ? 1 : maxSeconds;

    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final isToday = i == data.length - 1;
      final cx = slot * i + slot / 2;
      final barH = (d.totalActiveSeconds / safeMax) * chartH;
      final top = valueZone + (chartH - barH);

      // Bar
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, top, barW, barH < 2 ? 2 : barH),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      final paint = Paint()
        ..color = isToday
            ? AppColors.focus
            : AppColors.focus.withValues(alpha: 0.35);
      canvas.drawRRect(rect, paint);

      // Hour value above the bar (only when there is time)
      if (d.totalActiveSeconds > 0) {
        _text(
          canvas,
          Formatters.human(d.totalActiveSeconds),
          Offset(cx, top - valueZone + 1),
          color: Colors.white70,
          size: 10,
        );
      }

      // Weekday label under the bar
      _text(
        canvas,
        Formatters.weekdayShort(d.dateString),
        Offset(cx, size.height - labelZone + 3),
        color: isToday ? AppColors.focus : Colors.white54,
        size: 11,
        bold: isToday,
      );
    }
  }

  void _text(Canvas canvas, String text, Offset center,
      {required Color color, required double size, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) => old.data != data;
}
