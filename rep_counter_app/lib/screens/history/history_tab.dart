import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/line_chart.dart';
import '../home_shell.dart';
import '../workout/summary_screen.dart';
import 'progress_screen.dart';

class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SummaryScreen(session: session),
        ),
      ),
      child: Container(
        height: 72,
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
                  Text(session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.text(19,
                          weight: FontWeight.w500, color: c.ink)),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDay(session.startedAt)} · '
                    '${session.duration.inMinutes} min',
                    style: AppText.text(14, color: c.ink2),
                  ),
                ],
              ),
            ),
            NumberWithUnit(
              value: formatNumber(session.volumeKg),
              unit: 'kg',
              size: 28,
              unitSize: 13,
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  static const _visibleSessions = 4;
  String? _exerciseId;

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabHeader(title: 'Historial'),
        Expanded(
          child: ListenableBuilder(
            listenable: repo,
            builder: (context, _) {
              final c = context.colors;
              final sessions = repo.sessions;
              if (sessions.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(kGutter),
                  child: Text(
                    'Aquí aparecerán tus sesiones cuando termines la primera.',
                    style: AppText.text(17, color: c.ink2),
                  ),
                );
              }

              final withVelocity = repo.exercisesWithVelocity();
              final selected = withVelocity
                      .where((e) => e.id == _exerciseId)
                      .firstOrNull ??
                  withVelocity.firstOrNull;

              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kGutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AppLabel('Sesiones'),
                        for (final s in sessions.take(_visibleSessions))
                          SessionRow(session: s),
                        if (sessions.length > _visibleSessions)
                          _LinkRow(
                            label: 'Ver todas las sesiones '
                                '(${sessions.length})',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const AllSessionsScreen(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selected != null) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(kGutter, 32, kGutter, 12),
                      child: AppLabel('Velocidad media por ejercicio'),
                    ),
                    ChipRow(children: [
                      for (final e in withVelocity)
                        FillChip(
                          label: e.name,
                          selected: e.id == selected.id,
                          onTap: () => setState(() => _exerciseId = e.id),
                        ),
                    ]),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(kGutter, 20, kGutter, 0),
                      child: _VelocityPanel(exercise: selected),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VelocityPanel extends StatelessWidget {
  const _VelocityPanel({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    final c = context.colors;
    final points = <ChartPoint>[];
    for (final (session, sets) in repo.historyFor(exercise.id)) {
      final v = [for (final s in sets) ?s.meanVelocity];
      if (v.isEmpty) continue;
      points.add(ChartPoint(
        session.startedAt,
        v.reduce((a, b) => a + b) / v.length,
      ));
    }
    // The chart shows the last twelve sessions.
    final recent = points.length > 12
        ? points.sublist(points.length - 12)
        : points;
    final latest = recent.last.value;
    final change =
        recent.length > 1 ? latest - recent[recent.length - 2].value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatVelocity(latest), style: AppText.number(48, color: c.ink)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('m/s · última sesión',
                  style: AppText.text(15, color: c.ink2)),
            ),
            const Spacer(),
            if (change != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  formatSigned(change, decimals: 2),
                  style: AppText.text(15, weight: FontWeight.w600, color: c.ink),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LineChart(points: recent, format: formatVelocity, height: 120),
        const SizedBox(height: 8),
        Container(height: 1, color: c.line),
        _LinkRow(
          label: 'Ver todo el progreso',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProgressScreen(exercise: exercise),
            ),
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppText.text(16, weight: FontWeight.w600, color: c.ink)),
            ),
            AppIcon(AppIconKind.forward, color: c.ink),
          ],
        ),
      ),
    );
  }
}

class AllSessionsScreen extends StatelessWidget {
  const AllSessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 16),
              child: Text('Sesiones',
                  style: AppText.text(36,
                      weight: FontWeight.w500, height: 1.1, color: c.ink)),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: repo,
                builder: (context, _) => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: kGutter),
                  itemCount: repo.sessions.length,
                  itemBuilder: (context, i) =>
                      SessionRow(session: repo.sessions[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
