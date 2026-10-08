import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'exercise_browser.dart';

/// "Agregar a Empuje": check exercises and return them in the order they
/// were checked. With [single], the first tap returns that exercise.
class ExercisePickerScreen extends StatefulWidget {
  const ExercisePickerScreen({
    super.key,
    required this.title,
    this.single = false,
  });

  final String title;
  final bool single;

  @override
  State<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<ExercisePickerScreen> {
  final List<String> _order = [];

  void _toggle(Exercise exercise) {
    if (widget.single) {
      Navigator.of(context).pop([exercise]);
      return;
    }
    setState(() {
      if (!_order.remove(exercise.id)) _order.add(exercise.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    final n = _order.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ModalHeader(title: widget.title),
            const SizedBox(height: 16),
            Expanded(
              child: ExerciseBrowser(
                selected: widget.single ? null : _order.toSet(),
                showFavorites: false,
                initiallyExpanded: MuscleGroup.chest,
                onOpen: _toggle,
              ),
            ),
            if (!widget.single)
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 32),
                child: PrimaryButton(
                  label: n == 0
                      ? 'Agregar ejercicios'
                      : 'Agregar $n ${n == 1 ? 'ejercicio' : 'ejercicios'}',
                  onPressed: n == 0
                      ? null
                      : () => Navigator.of(context).pop([
                            for (final id in _order) ?repo.exercise(id),
                          ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
