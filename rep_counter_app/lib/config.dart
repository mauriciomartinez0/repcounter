// Build-time configuration. Values come from a JSON file:
//
//   flutter run   --dart-define-from-file=config/dev.json
//   flutter build appbundle --dart-define-from-file=config/prod.json

/// Base URL of the Rep Counter API, without a trailing slash.
const String kApiBaseUrl = String.fromEnvironment('API_BASE_URL');

/// Use the fake sensor instead of Bluetooth (testing without the board).
const bool kSimulateSensor = bool.fromEnvironment('SENSOR_SIM');
