// "Dónde va el sensor" drawing. The barbell follows the mockup exactly; the
// other placements reuse their icon at a large size until each gets its own
// illustration.

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

class SensorDiagram extends StatelessWidget {
  const SensorDiagram({super.key, required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (exercise.placement == SensorPlacement.equipment &&
        exercise.equipment == Equipment.barbell) {
      return Semantics(
        label: 'Barra con discos. El sensor va sobre la barra, en el centro.',
        child: AspectRatio(
          aspectRatio: 364 / 200,
          child: CustomPaint(painter: _BarbellPainter(c)),
        ),
      );
    }
    return Semantics(
      label: exercise.placementNote,
      child: SizedBox(
        height: 200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('SENSOR', style: AppText.label(c.mark, size: 13)),
            const SizedBox(height: 12),
            AppIcon(exercise.placement.icon, size: 120, strokeWidth: 1.2),
          ],
        ),
      ),
    );
  }
}

class _BarbellPainter extends CustomPainter {
  _BarbellPainter(this.c);

  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 364, size.height / 200);
    final stroke = Paint()
      ..color = c.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = c.bg;

    canvas.drawLine(
      const Offset(8, 110),
      const Offset(356, 110),
      Paint()
        ..color = c.ink
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    void plate(double x, double y, double w, double h, double r) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(r),
      );
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, stroke);
    }

    plate(44, 50, 14, 120, 3);
    plate(62, 66, 10, 88, 3);
    plate(76, 100, 8, 20, 2);
    plate(306, 50, 14, 120, 3);
    plate(292, 66, 10, 88, 3);
    plate(280, 100, 8, 20, 2);

    canvas.drawLine(
      const Offset(182, 62),
      const Offset(182, 92),
      Paint()
        ..color = c.mark
        ..strokeWidth = 1.5,
    );
    final sensor = RRect.fromRectAndRadius(
      const Rect.fromLTWH(166, 96, 32, 28),
      const Radius.circular(5),
    );
    canvas.drawRRect(sensor, Paint()..color = c.dot);
    if (c.dotRing.a > 0) {
      canvas.drawRRect(
        sensor,
        Paint()
          ..color = c.dotRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final label = TextPainter(
      text: TextSpan(text: 'SENSOR', style: AppText.label(c.mark, size: 13)),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(182 - label.width / 2, 36));
  }

  @override
  bool shouldRepaint(_BarbellPainter old) => old.c != c;
}
