import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import 'set_correction.dart';

/// "Sesión completada". Also opened from Historial for past sessions.
///
/// Right after a workout the sets can still be corrected: tapping an exercise
/// opens its sets, so the last set (which has no rest screen after it) can be
/// fixed too.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({
    super.key,
    required this.session,
    this.justFinished = false,
  });

  final WorkoutSession session;
  final bool justFinished;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late WorkoutSession session = widget.session;

  bool get justFinished => widget.justFinished;

  Future<void> _edit(String exerciseId, String name) async {
    final repo = context.app.repository;
    await editExerciseSets(
      context,
      exerciseName: name,
      sets: [for (final s in session.sets) if (s.exerciseId == exerciseId) s],
      onChanged: (corrected) {
        var k = 0;
        final sets = [
          for (final s in session.sets)
            s.exerciseId == exerciseId ? corrected[k++] : s,
        ];
        setState(() => session = session.copyWith(sets: sets));
        repo.saveSession(session);
      },
    );
  }

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

    void close() {
      if (justFinished) {
        // Corrections are over: now it can go to the server.
        repo.commitSession(session.id);
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
                      _ExerciseRow(
                        name: repo.exercise(id)?.name ?? id,
                        sets: [
                          for (final s in session.sets)
                            if (s.exerciseId == id) s,
                        ],
                        last: i == exerciseIds.length - 1,
                        onTap: justFinished
                            ? () => _edit(id, repo.exercise(id)?.name ?? id)
                            : null,
                      ),
                    if (justFinished) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Toca un ejercicio para corregir sus repeticiones.',
                        style: AppText.text(14, color: c.ink3),
                      ),
                    ],
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

/// How the sets of one exercise went.
///
/// When every set matched (same reps, same weight, target met) it reads like
/// the plan: "4 × 8 · 60 kg". Otherwise each set is listed so a drop-off is
/// visible: "60 kg: 12, 10, 9, 8", or "60 kg: 12, 10 · 55 kg: 9, 8" when the
/// weight changed between sets.
class SetsDescription {
  SetsDescription(List<SetRecord> sets)
      : compact = _isUniform(sets),
        text = _isUniform(sets)
            ? formatSetsSummary(sets.length, sets.first.reps, sets.first.weightKg)
            : _perSet(sets),
        target = _sharedTarget(sets),
        missedTarget = sets.any(
          (s) => s.targetReps != null && s.reps < s.targetReps!,
        );

  final bool compact;
  final String text;

  /// The target when every set had the same one.
  final int? target;
  final bool missedTarget;

  static bool _isUniform(List<SetRecord> sets) =>
      sets.every((s) =>
          s.reps == sets.first.reps &&
          s.weightKg == sets.first.weightKg &&
          (s.targetReps == null || s.reps >= s.targetReps!));

  static int? _sharedTarget(List<SetRecord> sets) {
    final target = sets.first.targetReps;
    return sets.every((s) => s.targetReps == target) ? target : null;
  }

  static String _perSet(List<SetRecord> sets) {
    // Consecutive sets with the same weight share one label.
    final groups = <(double?, List<int>)>[];
    for (final s in sets) {
      if (groups.isNotEmpty && groups.last.$1 == s.weightKg) {
        groups.last.$2.add(s.reps);
      } else {
        groups.add((s.weightKg, [s.reps]));
      }
    }
    return [
      for (final (kg, reps) in groups)
        '${kg == null ? 'corporal' : '${formatKg(kg)} kg'}: ${reps.join(', ')}',
    ].join(' · ');
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.name,
    required this.sets,
    required this.last,
    this.onTap,
  });

  final String name;
  final List<SetRecord> sets;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = SetsDescription(sets);
    final title = Text(
      name,
      overflow: TextOverflow.ellipsis,
      style: AppText.text(17, weight: FontWeight.w500, color: c.ink),
    );
    final row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.symmetric(vertical: d.compact ? 0 : 10),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: d.compact
          ? Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                Text(d.text, style: AppText.text(15, color: c.ink2)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    Text(
                      '${sets.length} ${plural(sets.length, 'serie', 'series')}',
                      style: AppText.text(15, color: c.ink2),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: d.text),
                    if (d.missedTarget && d.target != null)
                      TextSpan(
                        text: ' · objetivo ${d.target}',
                        style: TextStyle(color: c.ink3),
                      ),
                  ]),
                  style: AppText.text(15, color: c.ink2),
                ),
              ],
            ),
    );
    return onTap == null
        ? row
        : Pressable(
            onTap: onTap,
            semanticLabel: 'Corregir $name',
            child: row,
          );
  }
}

