// Correcting what the sensor counted. A set can come up short of the plan
// (12, 10, 9…) and the sensor can also miss or double-count a rep; either
// way the history should hold what was really done.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';

Future<T?> _sheet<T>(BuildContext context, Widget Function(BuildContext) body) {
  final c = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: c.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius * 2)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 24),
        child: body(context),
      ),
    ),
  );
}

/// Reps of one set. Returns the corrected count, or null if dismissed.
Future<int?> askReps(
  BuildContext context, {
  required String title,
  required int initial,
  int? target,
}) {
  var value = initial;
  return _sheet<int>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: AppText.text(22, weight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: 4),
            Text(
              target == null
                  ? 'Repeticiones que hiciste en esta serie.'
                  : 'Repeticiones que hiciste. El objetivo era $target.',
              style: AppText.text(16, color: c.ink2),
            ),
            const SizedBox(height: 24),
            Center(
              child: CountStepper(
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Listo',
              onPressed: () => Navigator.of(context).pop(value),
            ),
          ],
        );
      },
    ),
  );
}

/// All the sets of one exercise in a session, each with its own count.
/// [onChanged] receives the full, corrected list every time a value changes.
Future<void> editExerciseSets(
  BuildContext context, {
  required String exerciseName,
  required List<SetRecord> sets,
  required ValueChanged<List<SetRecord>> onChanged,
}) {
  var current = List.of(sets);
  return _sheet<void>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) {
        final c = context.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(exerciseName,
                style: AppText.text(22, weight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: 4),
            Text('Corrige las repeticiones de cada serie.',
                style: AppText.text(16, color: c.ink2)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, s) in current.indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.line)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Serie ${s.setNumber}',
                                    style: AppText.text(17,
                                        weight: FontWeight.w500,
                                        color: c.ink)),
                                Text(
                                  [
                                    s.weightKg == null
                                        ? 'corporal'
                                        : '${formatKg(s.weightKg!)} kg',
                                    if (s.targetReps != null)
                                      'objetivo ${s.targetReps}',
                                  ].join(' · '),
                                  style: AppText.text(14, color: c.ink2),
                                ),
                              ],
                            ),
                          ),
                          CountStepper(
                            value: s.reps,
                            onChanged: (v) {
                              setState(() {
                                current = [...current]
                                  ..[i] = s.copyWith(reps: v);
                              });
                              onChanged(current);
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Listo',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    ),
  );
}
