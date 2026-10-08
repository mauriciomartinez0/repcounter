import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Placement icon with its name underneath ("EQUIPO").
class PlacementTag extends StatelessWidget {
  const PlacementTag({super.key, required this.placement});

  final SensorPlacement placement;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(placement.icon, color: c.ink),
          const SizedBox(height: 2),
          Text(
            placement.label.toUpperCase(),
            style: AppText.text(11, weight: FontWeight.w600, color: c.ink2)
                .copyWith(letterSpacing: 11 * 0.06),
          ),
        ],
      ),
    );
  }
}

class ExerciseRow extends StatelessWidget {
  const ExerciseRow({
    super.key,
    required this.exercise,
    required this.onTap,
    this.checked,
  });

  final Exercise exercise;
  final VoidCallback onTap;

  /// Null hides the checkbox.
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.text(17,
                          weight: FontWeight.w500, color: c.ink)),
                  const SizedBox(height: 2),
                  Text(exercise.equipment.label,
                      style: AppText.text(13, color: c.ink2)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PlacementTag(placement: exercise.placement),
            if (checked != null) ...[
              const SizedBox(width: 12),
              AppCheckbox(checked: checked!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Search, quick picks, equipment filter and muscle groups. Used by the
/// Ejercicios tab (open an exercise) and by the picker (check exercises).
class ExerciseBrowser extends StatefulWidget {
  const ExerciseBrowser({
    super.key,
    required this.onOpen,
    this.selected,
    this.showFavorites = true,
    this.initiallyExpanded,
  });

  /// Tap on an exercise or a quick-pick chip.
  final ValueChanged<Exercise> onOpen;

  /// When not null, rows show a checkbox reflecting this set.
  final Set<String>? selected;
  final bool showFavorites;
  final MuscleGroup? initiallyExpanded;

  @override
  State<ExerciseBrowser> createState() => _ExerciseBrowserState();
}

class _ExerciseBrowserState extends State<ExerciseBrowser> {
  final _search = TextEditingController();
  String _query = '';
  Equipment? _equipment;
  late final Set<MuscleGroup> _expanded = {?widget.initiallyExpanded};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final c = context.colors;
        final query = _fold(_query.trim());
        final filtered = [
          for (final e in repo.exercises)
            if ((_equipment == null || e.equipment == _equipment) &&
                (query.isEmpty || _fold(e.name).contains(query)))
              e,
        ];
        final recents = repo.recentExercises();
        final favorites = repo.favoriteExercises;
        final selected = widget.selected;

        Widget row(Exercise e) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter),
              child: ExerciseRow(
                exercise: e,
                checked: selected?.contains(e.id),
                onTap: () => widget.onOpen(e),
              ),
            );

        Widget section(String label) => Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 8),
              child: AppLabel(label),
            );

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter),
              child: SearchField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (query.isEmpty && recents.isNotEmpty) ...[
              section('Recientes'),
              ChipRow(children: [
                for (final e in recents)
                  OutlineChip(
                    label: e.name,
                    icon: e.equipment.icon,
                    onTap: () => widget.onOpen(e),
                  ),
              ]),
            ],
            if (query.isEmpty && widget.showFavorites && favorites.isNotEmpty) ...[
              section('Favoritos'),
              ChipRow(children: [
                for (final e in favorites)
                  OutlineChip(
                    label: e.name,
                    icon: e.equipment.icon,
                    onTap: () => widget.onOpen(e),
                  ),
              ]),
            ],
            section('Equipo'),
            ChipRow(children: [
              for (final eq in Equipment.values)
                FillChip(
                  label: eq.label,
                  icon: eq.icon,
                  fontSize: 14,
                  selected: _equipment == eq,
                  onTap: () => setState(
                    () => _equipment = _equipment == eq ? null : eq,
                  ),
                ),
            ]),
            if (query.isNotEmpty) ...[
              section('Resultados'),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kGutter),
                  child: Text('Ningún ejercicio coincide con "$_query".',
                      style: AppText.text(16, color: c.ink2)),
                ),
              for (final e in filtered) row(e),
            ] else ...[
              section('Grupo muscular'),
              for (final group in MuscleGroup.values) ...[
                () {
                  final inGroup = [
                    for (final e in filtered)
                      if (e.muscleGroup == group) e,
                  ];
                  final open = _expanded.contains(group);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Pressable(
                        onTap: () => setState(() {
                          if (!_expanded.remove(group)) _expanded.add(group);
                        }),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: kGutter),
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: open ? c.ink : c.line,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(group.label,
                                      style: AppText.text(19,
                                          weight: open
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: c.ink)),
                                ),
                                Text('${inGroup.length}',
                                    style: AppText.number(22, color: c.ink2)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (open) for (final e in inGroup) row(e),
                    ],
                  );
                }(),
              ],
            ],
          ],
        );
      },
    );
  }
}
