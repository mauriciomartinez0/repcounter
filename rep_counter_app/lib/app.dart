import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'screens/auth/login_screen.dart';
import 'screens/connection_screen.dart';
import 'theme/app_theme.dart';

class RepCounterApp extends StatelessWidget {
  const RepCounterApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) => MaterialApp(
          title: 'Rep Counter',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode:
              services.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
          // Signed in: connect the sensor first, then pick a routine, as in
          // the "Conectar y elegir rutina" flow.
          home: services.auth.signedIn
              ? const ConnectionScreen()
              : const LoginScreen(),
        ),
      ),
    );
  }
}
