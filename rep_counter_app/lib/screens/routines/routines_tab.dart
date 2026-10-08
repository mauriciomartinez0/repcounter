import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../home_shell.dart';
import 'routine_detail_screen.dart';
import 'routine_editor_screen.dart';

class RoutinesTab extends StatelessWidget {
  const RoutinesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabHeader(title: 'Rutinas'),
        Expanded(
          child: ListenableBuilder(
            listenable: repo,
            builder: (context, _) {
              final c = context.colors;
              final routines = repo.routines;
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: kGutter),
                children: [
                  Container(height: 1, color: c.line),
                  for (final routine in routines)
                    Pressable(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              RoutineDetailScreen(routineId: routine.id),
                        ),
                      ),
                      child: Container(
                        height: 96,
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: c.line)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(routine.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.text(26,
                                    weight: FontWeight.w500,
                                    height: 1.15,
                                    color: c.ink)),
                            const SizedBox(height: 4),
                            Text(routineSubtitle(routine),
                                style: AppText.text(15, color: c.ink2)),
                          ],
                        ),
                      ),
                    ),
                  Pressable(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RoutineEditorScreen(),
                      ),
                    ),
                    child: SizedBox(
                      height: 72,
                      child: Row(
                        children: [
                          AppIcon(AppIconKind.plus, color: c.ink),
                          const SizedBox(width: 12),
                          Text('Nueva rutina',
                              style: AppText.text(18,
                                  weight: FontWeight.w600, color: c.ink)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGutter),
          child: Pressable(
            onTap: () => HomeShell.selectTab(context, 1),
            child: Container(
              height: 92,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.colors.line)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Entrenamiento libre',
                      style: AppText.text(17,
                          weight: FontWeight.w600, color: context.colors.ink)),
                  const SizedBox(height: 2),
                  Text('Sin rutina. Eliges ejercicios sobre la marcha.',
                      style: AppText.text(14, color: context.colors.ink2)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
