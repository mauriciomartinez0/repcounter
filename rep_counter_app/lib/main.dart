// Rep counter: connects to the XIAO nRF52840 Sense over BLE, organizes the
// workout in routines, and shows the count the board computes.
//
// Run with `--dart-define=SENSOR_SIM=true` to use a simulated sensor.

import 'package:flutter/material.dart';

import 'app.dart';
import 'app_scope.dart';
import 'data/repository.dart';
import 'data/session_controllers.dart';
import 'sensor/sensor_service.dart';

const bool kSimulateSensor = bool.fromEnvironment('SENSOR_SIM');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = AppServices(
    repository: LocalGymRepository(),
    auth: AuthController(),
    settings: SettingsController(),
    sensor: kSimulateSensor ? SimulatedSensorService() : BleSensorService(),
  );
  await services.load();
  runApp(RepCounterApp(services: services));
}
