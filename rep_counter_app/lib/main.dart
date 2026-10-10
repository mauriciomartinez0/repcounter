// Rep counter: connects to the XIAO nRF52840 Sense over BLE, organizes the
// workout in routines, and keeps the history on the Rep Counter API.
//
//   flutter run --dart-define-from-file=config/dev.json
//   flutter build appbundle --dart-define-from-file=config/prod.json

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app.dart';
import 'app_scope.dart';
import 'config.dart';
import 'data/local_store.dart';
import 'data/remote_repository.dart';
import 'data/session_controllers.dart';
import 'sensor/sensor_service.dart';
import 'theme/app_theme.dart';

/// Why the build cannot run, or null if the configuration is usable.
String? configurationProblem(String baseUrl, {required bool release}) {
  if (baseUrl.isEmpty) {
    return 'Falta API_BASE_URL. Compila con '
        '--dart-define-from-file=config/prod.json (o dev.json).';
  }
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'API_BASE_URL no es una URL válida: $baseUrl';
  }
  if (release && uri.scheme != 'https') {
    return 'En producción API_BASE_URL debe usar https: $baseUrl';
  }
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final problem = configurationProblem(kApiBaseUrl, release: kReleaseMode);
  if (problem != null) {
    runApp(_ConfigurationError(problem));
    return;
  }

  final api = ApiClient(baseUrl: kApiBaseUrl, tokens: SecureTokenStore());
  final services = AppServices(
    api: api,
    repository: RemoteGymRepository(api: api, store: FileLocalStore()),
    auth: AuthController(api: api),
    settings: SettingsController(),
    sensor: kSimulateSensor ? SimulatedSensorService() : BleSensorService(),
  );
  await services.load();
  runApp(RepCounterApp(services: services));
}

/// A build without a server address must say so instead of failing on every
/// screen with network errors.
class _ConfigurationError extends StatelessWidget {
  const _ConfigurationError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(kGutter),
              child: Center(
                child: Text(message, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      );
}
