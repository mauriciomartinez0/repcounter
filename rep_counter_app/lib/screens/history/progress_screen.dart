import 'dart:math';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/line_chart.dart';

/// One way of reading a session's sets of an exercise.
enum ProgressMetric {
  weight('Peso', 'kg', 'Peso máximo por sesión', step: true),
  reps('Repeticiones', 'reps', 'Repeticiones totales por sesión'),
  volume('Volumen', 'kg', 'Volumen por sesión'),
  oneRepMax('1RM estimado', 'kg', '1RM estimado por sesión'),
  velocity('Velocidad', 'm/s', 'Velocidad media por sesión'),
  range('Rango', '°', 'Rango de movimiento máximo por sesión');

  const ProgressMetric(this.label, this.unit, this.caption,
      {this.step = false});

  final String label;
  final String unit;
  final String caption;
  final bool step;

  double? valueOf(List<SetRecord> sets) {
    double? best(Iterable<double> xs) => xs.isEmpty ? null : xs.reduce(max);
    switch (this) {
      case weight:
        return best([for (final s in sets) ?s.weightKg]);
      case reps:
        return sets.fold<int>(0, (sum, s) => sum + s.reps).toDouble();
      case volume:
        final v = sets.fold<double>(0, (sum, s) => sum + s.volumeKg);
        return v == 0 ? null : v;
      case oneRepMax:
        // Epley: weight × (1 + reps / 30).
        return best([
          for (final s in sets)
            if (s.weightKg != null) s.weightKg! * (1 + s.reps / 30),
        ]);
      case velocity:
        final v = [for (final s in sets) ?s.meanVelocity];
        return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
      case range:
        return best([for (final s in sets) ?s.rangeDegrees]);
    }
  }

  String format(double v) => switch (this) {
        velocity => formatVelocity(v),
        weight || oneRepMax => formatNumber(v, decimals: 1),
        _ => formatNumber(v),
      };
}

enum ProgressRange {
  weeks4('4 semanas', 28),
  weeks12('12 semanas', 84),
  all('Todo', null);

  const ProgressRange(this.label, this.days);
  final String label;
  final int? days;
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.exercise});

  final Exercise exercise;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  ProgressMetric _metric = ProgressMetric.weight;
  ProgressRange _range = ProgressRange.weeks12;

  @override
  void initState() {
    super.initState();
    // Body-weight exercises have no load; start on something they have.
    final history = context.app.repository.historyFor(widget.exercise.id);
    final hasWeight = history.any(
      (h) => ProgressMetric.weight.valueOf(h.$2) != null,
    );
    if (!hasWeight) _metric = ProgressMetric.reps;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    final c = context.colors;
    final now = DateTime.now();
    final days = _range.days;
    final points = <ChartPoint>[];
    for (final (session, sets) in repo.historyFor(widget.exercise.id)) {
      if (days != null &&
          now.difference(session.startedAt).inDays > days) {
        continue;
      }
      final v = _metric.valueOf(sets);
      if (v != null) points.add(ChartPoint(session.startedAt, v));
    }

    final latest = points.lastOrNull;
    final bestPoint = points.isEmpty
        ? null
        : points.reduce((a, b) => b.value >= a.value ? b : a);
    final average = points.isEmpty
        ? null
        : points.map((p) => p.value).reduce((a, b) => a + b) / points.length;
    final change =
        points.length < 2 ? null : points.last.value - points.first.value;

    Widget stat(String label, String? value, String footnote) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: StatCell(
              label: label,
              value: NumberWithUnit(
                value: value ?? '—',
                unit: value == null ? null : _metric.unit,
                size: 28,
                unitSize: 13,
              ),
              footnote: footnote,
            ),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 32),
                children: [
                  Text(widget.exercise.name,
                      style: AppText.text(36,
                          weight: FontWeight.w500, height: 1.1, color: c.ink)),
                  const SizedBox(height: 6),
                  Text('Progreso', style: AppText.text(16, color: c.ink2)),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in ProgressMetric.values)
                        FillChip(
                          label: m.label,
                          selected: m == _metric,
                          onTap: () => setState(() => _metric = m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  NumberWithUnit(
                    value: latest == null ? '—' : _metric.format(latest.value),
                    unit: latest == null ? null : _metric.unit,
                    size: 64,
                    unitSize: 18,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    latest == null
                        ? '${_metric.caption} · sin datos en este periodo'
                        : '${_metric.caption} · última sesión, '
                            '${formatShortDate(latest.date)}',
                    style: AppText.text(14, color: c.ink2),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      for (final r in ProgressRange.values) ...[
                        Pressable(
                          onTap: () => setState(() => _range = r),
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: r == _range
                                      ? c.mark
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(r.label,
                                style: AppText.text(15,
                                    weight: r == _range
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: r == _range ? c.ink : c.ink2)),
                          ),
                        ),
                        const SizedBox(width: 24),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  LineChart(
                    points: points,
                    format: _metric.format,
                    step: _metric.step,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.symmetric(
                        horizontal: BorderSide(color: c.line),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          stat(
                            'Mejor marca',
                            bestPoint == null
                                ? null
                                : _metric.format(bestPoint.value),
                            bestPoint == null
                                ? ''
                                : formatShortDate(bestPoint.date),
                          ),
                          Container(width: 1, color: c.line),
                          const SizedBox(width: 14),
                          stat(
                            'Promedio',
                            average == null ? null : _metric.format(average),
                            'por sesión',
                          ),
                          Container(width: 1, color: c.line),
                          const SizedBox(width: 14),
                          stat(
                            'Cambio',
                            change == null
                                ? null
                                : (change > 0 ? '+' : '') +
                                    _metric.format(change),
                            _range == ProgressRange.all
                                ? 'desde el inicio'
                                : 'en ${_range.label}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
