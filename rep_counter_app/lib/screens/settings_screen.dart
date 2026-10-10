import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/repository.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Tries to upload pending changes first; if some cannot go up, asks
  /// before deleting them along with this phone's copy of the account.
  Future<void> _signOut(BuildContext context) async {
    final app = context.app;
    final repo = app.repository;
    if (repo.pendingChanges > 0) await repo.sync();
    if (!context.mounted) return;
    final pending = repo.pendingChanges;
    if (pending > 0) {
      final ok = await confirm(
        context,
        title: '¿Cerrar sesión sin subir todo?',
        message: 'Hay $pending ${plural(pending, 'cambio', 'cambios')} que '
            'todavía no llegó al servidor, probablemente por falta de '
            'internet. Si cierras sesión ahora, se pierden.',
        confirmLabel: 'Cerrar sesión',
      );
      if (!ok) return;
    }
    await app.sensor.cancel();
    await repo.discardUserData();
    // The app returns to the login screen on its own when the session ends.
    await app.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = context.colors;
    final user = app.auth.user;

    Widget accountRow(String label, String value) => Container(
          height: 64,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Text(label, style: AppText.text(16, color: c.ink2)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.text(17, weight: FontWeight.w500, color: c.ink),
                ),
              ),
            ],
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
                padding: const EdgeInsets.symmetric(horizontal: kGutter),
                children: [
                  const SizedBox(height: 8),
                  Text('Ajustes',
                      style: AppText.text(36,
                          weight: FontWeight.w500, height: 1.1, color: c.ink)),
                  const SizedBox(height: 32),
                  const AppLabel('Apariencia'),
                  const SizedBox(height: 4),
                  ListenableBuilder(
                    listenable: app.settings,
                    builder: (context, _) => Container(
                      height: 84,
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.line)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Modo oscuro',
                                style: AppText.text(19,
                                    weight: FontWeight.w500, color: c.ink)),
                          ),
                          AppSwitch(
                            label: 'Modo oscuro',
                            value: app.settings.darkMode,
                            onChanged: app.settings.setDarkMode,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const AppLabel('Cuenta'),
                  const SizedBox(height: 4),
                  accountRow('Nombre', user?.name ?? '—'),
                  accountRow('Correo', user?.email ?? '—'),
                  const SizedBox(height: 32),
                  const AppLabel('Sincronización'),
                  const SizedBox(height: 4),
                  const _SyncStatusRow(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 32),
              child: SecondaryButton(
                label: 'Cerrar sesión',
                onPressed: () => _signOut(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  const _SyncStatusRow();

  @override
  Widget build(BuildContext context) {
    final repo = context.app.repository;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final c = context.colors;
        final pending = repo.pendingChanges;
        final last = repo.lastSyncedAt;
        final status = switch (repo.syncStatus) {
          SyncStatus.syncing => 'Sincronizando…',
          SyncStatus.offline => 'Sin conexión. Se reintenta solo.',
          SyncStatus.error => 'El servidor no respondió bien. Se reintenta solo.',
          SyncStatus.idle when pending > 0 =>
            '$pending ${plural(pending, 'cambio pendiente', 'cambios pendientes')}',
          SyncStatus.idle => last == null
              ? 'Todavía no se sincroniza.'
              : 'Al día · ${formatDay(last)}, '
                  '${last.hour}:${last.minute.toString().padLeft(2, '0')}',
        };
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(status,
                        style: AppText.text(17,
                            weight: FontWeight.w500, color: c.ink)),
                  ),
                  TextAction(
                    label: 'Sincronizar',
                    weight: FontWeight.w600,
                    color: c.ink,
                    onPressed: repo.syncStatus == SyncStatus.syncing
                        ? null
                        : repo.sync,
                  ),
                ],
              ),
              if (repo.syncIssue != null) ...[
                const SizedBox(height: 4),
                Text(repo.syncIssue!, style: AppText.text(14, color: c.ink2)),
              ],
            ],
          ),
        );
      },
    );
  }
}
