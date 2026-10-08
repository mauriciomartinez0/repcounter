import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'auth/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 32),
              child: SecondaryButton(
                label: 'Cerrar sesión',
                onPressed: () async {
                  await app.auth.signOut();
                  await app.sensor.cancel();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
