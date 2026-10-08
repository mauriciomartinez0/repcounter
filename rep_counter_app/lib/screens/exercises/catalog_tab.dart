import 'package:flutter/material.dart';

import '../home_shell.dart';
import 'exercise_browser.dart';
import 'exercise_detail_screen.dart';

/// "Ejercicios" tab: explore the catalog and open an exercise.
class CatalogTab extends StatelessWidget {
  const CatalogTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabHeader(title: 'Ejercicios'),
        Expanded(
          child: ExerciseBrowser(
            onOpen: (exercise) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExerciseDetailScreen(exercise: exercise),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
