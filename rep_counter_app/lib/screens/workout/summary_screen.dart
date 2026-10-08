import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';

/// "Sesión completada". Also opened from Historial for past sessions.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({
    super.key,
    required this.session,
    this.justFinished = false,
  });

  final WorkoutSession session;
  final bool justFinished;

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    final c = context.colors;
    final previous = repo.previousSession(session);
    final minutes = session.duration.inMinutes;
    final exerciseIds = session.exerciseIds;

    final countText = session.plannedExercises > 0
        ? '${exerciseIds.length} de ${session.plannedExercises} ejercicios'
        : '${exerciseIds.length} '
            '${plural(exerciseIds.length, 'ejercicio', 'ejercicios')}';

    String exerciseLine(String id) {
      final sets = [for (final s in session.sets) if (s.exerciseId == id) s];
      // Most frequent rep count reads as the plan ("4 × 8").
      final counts = <int, int>{};
      for (final s in sets) {
        counts[s.reps] = (counts[s.reps] ?? 0) + 1;
      }
      final reps = (counts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;
      final weights = [for (final s in sets) ?s.weightKg];
      final top = weights.isEmpty ? null : weights.reduce((a, b) => a > b ? a : b);
      return formatSetsSummary(sets.length, reps, top);
    }

    void close() {
      if (justFinished) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.of(context).pop();
      }
    }

    return PopScope(
      canPop: !justFinished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!justFinished) const BackHeader(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                      kGutter, justFinished ? 40 : 8, kGutter, 24),
                  children: [
                    if (justFinished) ...[
                      const AppLabel('Sesión completada'),
                      const SizedBox(height: 4),
                    ],
                    Text(session.title,
                        style: AppText.text(36,
                            weight: FontWeight.w500, height: 1.1, color: c.ink)),
                    const SizedBox(height: 6),
                    Text('${formatDay(session.startedAt)} · $countText',
                        style: AppText.text(16, color: c.ink2)),
                    const SizedBox(height: 28),
                    StatPair(
                      left: StatCell(
                        label: 'Volumen total',
                        value: NumberWithUnit(
                          value: formatNumber(session.volumeKg),
                          unit: 'kg',
                          size: 64,
                          unitSize: 18,
                        ),
                        footnote: previous == null
                            ? null
                            : '${formatSigned(session.volumeKg - previous.volumeKg)} kg',
                        footnoteColor:
                            session.volumeKg >= (previous?.volumeKg ?? 0)
                                ? c.mark
                                : c.ink,
                      ),
                      right: StatCell(
                        label: 'Duración',
                        value: NumberWithUnit(
                          value: '$minutes',
                          unit: 'min',
                          size: 64,
                          unitSize: 18,
                        ),
                        footnote: previous == null
                            ? null
                            : '${formatSigned(minutes - previous.duration.inMinutes)} min',
                        footnoteColor: c.ink,
                      ),
                    ),
                    if (previous != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Comparado con la última vez: '
                        '${formatDayLower(previous.startedAt)}.',
                        style: AppText.text(14, color: c.ink2),
                      ),
                    ],
                    const SizedBox(height: 32),
                    const AppLabel('Ejercicios'),
                    const SizedBox(height: 4),
                    for (final (i, id) in exerciseIds.indexed)
                      Container(
                        height: 52,
                        decoration: BoxDecoration(
                          border: i == exerciseIds.length - 1
                              ? null
                              : Border(bottom: BorderSide(color: c.line)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                repo.exercise(id)?.name ?? id,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.text(17,
                                    weight: FontWeight.w500, color: c.ink),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(exerciseLine(id),
                                style: AppText.text(15, color: c.ink2)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (justFinished)
                Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 32),
                  child: PrimaryButton(label: 'Listo', onPressed: close),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
