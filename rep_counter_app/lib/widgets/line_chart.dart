// Minimal chart from the mockups: lines at the top and bottom of the range
// with their values, one ink line, and the sensor dot on the latest point.

import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/format.dart';

class ChartPoint {
  const ChartPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.points,
    required this.format,
    this.step = false,
    this.height = 170,
  });

  final List<ChartPoint> points;
  final String Function(double) format;

  /// Draw as steps (weights move in jumps, not slopes).
  final bool step;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Todavía no hay datos.',
              style: AppText.text(15, color: c.ink2)),
        ),
      );
    }
    final values = points.map((p) => p.value);
    var lo = values.reduce(min);
    var hi = values.reduce(max);
    if (hi == lo) {
      hi += hi == 0 ? 1 : hi * 0.1;
      lo -= lo == 0 ? 0 : lo * 0.1;
    }
    return Semantics(
      label: 'Gráfica de ${points.length} puntos, de ${format(lo)} a '
          '${format(hi)}. Último valor ${format(points.last.value)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(format(hi), style: AppText.text(11, color: c.ink2)),
          const SizedBox(height: 4),
          SizedBox(
            height: height,
            child: CustomPaint(
              painter: _ChartPainter(
                points: points,
                lo: lo,
                hi: hi,
                step: step,
                colors: c,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(format(lo), style: AppText.text(11, color: c.ink2)),
          const SizedBox(height: 10),
          DefaultTextStyle(
            style: AppText.text(13, color: c.ink2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatShortDate(points.first.date)),
                if (points.length > 1) Text(formatShortDate(points.last.date)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.lo,
    required this.hi,
    required this.step,
    required this.colors,
  });

  final List<ChartPoint> points;
  final double lo;
  final double hi;
  final bool step;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0; // keeps the end dot inside the box
    final rule = Paint()
      ..color = colors.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, inset), Offset(size.width, inset), rule);
    canvas.drawLine(Offset(0, size.height - inset),
        Offset(size.width, size.height - inset), rule);

    final first = points.first.date.millisecondsSinceEpoch.toDouble();
    final last = points.last.date.millisecondsSinceEpoch.toDouble();
    final span = max(1.0, last - first);
    final h = size.height - 2 * inset;
    final w = size.width - 2 * inset;

    Offset at(ChartPoint p) {
      final x = points.length == 1
          ? size.width - inset
          : inset + (p.date.millisecondsSinceEpoch - first) / span * w;
      final y = inset + (1 - (p.value - lo) / (hi - lo)) * h;
      return Offset(x, y);
    }

    final path = Path();
    for (final (i, p) in points.indexed) {
      final o = at(p);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else if (step) {
        final prev = at(points[i - 1]);
        // Hold the previous value, then rise over a short ramp, as drawn.
        final ramp = min(18.0, (o.dx - prev.dx) / 2);
        path.lineTo(o.dx - ramp, prev.dy);
        path.lineTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final end = at(points.last);
    canvas.drawCircle(end, 5, Paint()..color = colors.dot);
    canvas.drawCircle(
      end,
      5,
      Paint()
        ..color = colors.dotRing.a == 0 ? colors.dot : colors.dotRing
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points ||
      old.lo != lo ||
      old.hi != hi ||
      old.colors != colors ||
      old.step != step;
}
