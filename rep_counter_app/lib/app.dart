import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'screens/auth/login_screen.dart';
import 'screens/connection_screen.dart';
import 'theme/app_theme.dart';

class RepCounterApp extends StatefulWidget {
  const RepCounterApp({super.key, required this.services});

  final AppServices services;

  @override
  State<RepCounterApp> createState() => _RepCounterAppState();
}

class _RepCounterAppState extends State<RepCounterApp>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  late bool _signedIn = widget.services.auth.signedIn;

  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _services.auth.addListener(_onAuth);
    if (_signedIn) _services.auth.refreshProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _services.auth.removeListener(_onAuth);
    super.dispose();
  }

  /// Back to the login screen whenever the session ends: signing out, or the
  /// server rejecting the session (password changed elsewhere, token stolen).
  void _onAuth() {
    final signedIn = _services.auth.signedIn;
    if (_signedIn && !signedIn) {
      _navigator.currentState?.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
    _signedIn = signedIn;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is the natural moment to catch up: changes
    // from another phone, or uploads that waited for signal.
    if (state == AppLifecycleState.resumed && _services.auth.signedIn) {
      _services.repository.sync();
      _services.auth.refreshProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: _services,
      child: ListenableBuilder(
        listenable: _services.settings,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigator,
          title: 'Rep Counter',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode:
              _services.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
          // Signed in: connect the sensor first, then pick a routine, as in
          // the "Conectar y elegir rutina" flow.
          home: _services.auth.signedIn
              ? const ConnectionScreen()
              : const LoginScreen(),
        ),
      ),
    );
  }
}
