import 'package:flutter/widgets.dart';

import 'api/api_client.dart';
import 'data/repository.dart';
import 'data/session_controllers.dart';
import 'sensor/sensor_service.dart';

/// The app's long-lived services. Screens reach them with `context.app`.
class AppServices {
  AppServices({
    required this.repository,
    required this.auth,
    required this.settings,
    required this.sensor,
    this.api,
  });

  final GymRepository repository;
  final AuthController auth;
  final SettingsController settings;
  final SensorService sensor;
  final ApiClient? api;

  Future<void> load() async {
    await Future.wait([repository.load(), auth.load(), settings.load()]);
    // The repository follows the signed-in user: their data loads on sign
    // in, and on sign out or an expired session nothing of theirs stays on
    // screen.
    await repository.switchUser(auth.user?.id);
    auth.addListener(() => repository.switchUser(auth.user?.id));
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      services != oldWidget.services;
}

extension AppScopeContext on BuildContext {
  AppServices get app => AppScope.of(this);
}
