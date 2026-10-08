// Link to the XIAO nRF52840 Sense.
//
// The counting happens on the board, not here. The app selects the exercise,
// resets the count, and displays state. That split keeps counting working even
// if the phone screen locks or the connection drops for a moment.
//
// [BleSensorService] talks to the real board. [SimulatedSensorService] fakes
// it so every screen can be tried without hardware: run with
// `--dart-define=SENSOR_SIM=true`.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// Must match the firmware.
final Guid kServiceUuid = Guid('a1b20001-7f3c-4e8d-9a6b-2c5d8e0f1a3b');
final Guid kStateUuid = Guid('a1b20002-7f3c-4e8d-9a6b-2c5d8e0f1a3b');
final Guid kControlUuid = Guid('a1b20003-7f3c-4e8d-9a6b-2c5d8e0f1a3b');

const int kCmdSetExercise = 0x01;
const int kCmdResetCount = 0x02;
const int kCmdRezero = 0x03;

/// Everything the board publishes in one notification.
///
/// Bytes 0–5 are what the current firmware sends. Bytes 6–7 are optional:
/// the mean velocity of the last rep in mm/s, which the rest screen and the
/// history show. Firmware that does not send them still works; the velocity
/// just shows as "—".
class DeviceState {
  const DeviceState({
    required this.repCount,
    required this.angleDegrees,
    required this.exerciseId,
    required this.inUpPhase,
    required this.referenceCaptured,
    this.lastRepVelocity,
  });

  final int repCount;
  final double angleDegrees;
  final int exerciseId;
  final bool inUpPhase;

  /// False while the board is still waiting for a second of stillness to
  /// learn the resting pose. Until then it cannot count anything.
  final bool referenceCaptured;

  /// m/s, null when the firmware does not report it.
  final double? lastRepVelocity;

  static const DeviceState empty = DeviceState(
    repCount: 0,
    angleDegrees: 0,
    exerciseId: 0,
    inUpPhase: false,
    referenceCaptured: false,
  );

  static DeviceState? parse(List<int> raw) {
    if (raw.length < 6) return null;
    final bytes = ByteData.sublistView(Uint8List.fromList(raw));
    double? velocity;
    if (raw.length >= 8) {
      final mmPerSecond = bytes.getUint16(6, Endian.little);
      if (mmPerSecond > 0) velocity = mmPerSecond / 1000.0;
    }
    return DeviceState(
      repCount: bytes.getUint16(0, Endian.little),
      angleDegrees: bytes.getInt16(2, Endian.little) / 10.0,
      exerciseId: bytes.getUint8(4),
      inUpPhase: (bytes.getUint8(5) & 0x01) != 0,
      referenceCaptured: (bytes.getUint8(5) & 0x02) != 0,
      lastRepVelocity: velocity,
    );
  }
}

enum SensorStatus { idle, scanning, connecting, ready, failed }

enum SensorFailure { notFound, lost, unsupported, error }

abstract class SensorService extends ChangeNotifier {
  SensorStatus get status;
  SensorFailure? get failure;

  /// Technical detail of the last failure, for the error screen.
  String get detail;
  DeviceState get state;

  bool get connected => status == SensorStatus.ready;
  bool get busy =>
      status == SensorStatus.scanning || status == SensorStatus.connecting;

  Future<void> connect();
  Future<void> cancel();

  Future<void> setExercise(int firmwareProfile);
  Future<void> resetCount();

  /// Forget the resting pose and learn it again. The board clears
  /// [DeviceState.referenceCaptured] until the user holds still.
  Future<void> rezero();
}

class BleSensorService extends SensorService {
  SensorStatus _status = SensorStatus.idle;
  SensorFailure? _failure;
  String _detail = '';
  DeviceState _state = DeviceState.empty;
  int _exerciseId = 0;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _stateCharacteristic;
  BluetoothCharacteristic? _controlCharacteristic;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _stateSubscription;
  Timer? _scanTimeout;

  @override
  SensorStatus get status => _status;
  @override
  SensorFailure? get failure => _failure;
  @override
  String get detail => _detail;
  @override
  DeviceState get state => _state;

  void _set(SensorStatus status, [SensorFailure? failure, String detail = '']) {
    _status = status;
    _failure = failure;
    _detail = detail;
    notifyListeners();
  }

  @override
  Future<void> connect() async {
    if (busy || connected) return;
    _set(SensorStatus.scanning);

    try {
      if (await FlutterBluePlus.isSupported == false) {
        _set(SensorStatus.failed, SensorFailure.unsupported,
            'Este teléfono no soporta Bluetooth LE.');
        return;
      }

      // On Android the adapter can be turned on from the app.
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }

      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        if (results.isEmpty || _status != SensorStatus.scanning) return;
        _scanTimeout?.cancel();
        await FlutterBluePlus.stopScan();
        await _scanSubscription?.cancel();
        await _connectTo(results.first.device);
      });

      await FlutterBluePlus.startScan(
        withServices: [kServiceUuid],
        timeout: const Duration(seconds: 15),
      );

      // If the scan window closes without a hit, say so instead of hanging.
      _scanTimeout?.cancel();
      _scanTimeout = Timer(const Duration(seconds: 16), () {
        if (_status == SensorStatus.scanning) {
          _set(SensorStatus.failed, SensorFailure.notFound);
        }
      });
    } catch (error) {
      _set(SensorStatus.failed, SensorFailure.error, '$error');
    }
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    _set(SensorStatus.connecting);
    _device = device;

    await _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected &&
          _status == SensorStatus.ready) {
        _set(SensorStatus.failed, SensorFailure.lost);
      }
    });

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
      final services = await device.discoverServices();

      final service = services.firstWhere(
        (candidate) => candidate.uuid == kServiceUuid,
        orElse: () => throw Exception('El servicio no está en este dispositivo'),
      );

      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == kStateUuid) {
          _stateCharacteristic = characteristic;
        } else if (characteristic.uuid == kControlUuid) {
          _controlCharacteristic = characteristic;
        }
      }

      if (_stateCharacteristic == null || _controlCharacteristic == null) {
        throw Exception('Faltan características en el servicio');
      }

      await _stateCharacteristic!.setNotifyValue(true);
      await _stateSubscription?.cancel();
      _stateSubscription = _stateCharacteristic!.lastValueStream.listen((raw) {
        final parsed = DeviceState.parse(raw);
        if (parsed != null) {
          _state = parsed;
          notifyListeners();
        }
      });

      _set(SensorStatus.ready);
      // After a reconnect the board may have restarted; tell it again what
      // we are counting.
      await setExercise(_exerciseId);
    } catch (error) {
      _set(SensorStatus.failed, SensorFailure.error, '$error');
    }
  }

  @override
  Future<void> cancel() async {
    _scanTimeout?.cancel();
    await _scanSubscription?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _device?.disconnect();
    _set(SensorStatus.idle);
  }

  Future<void> _send(List<int> bytes) async {
    final control = _controlCharacteristic;
    if (control == null || !connected) return;
    try {
      await control.write(bytes, withoutResponse: false);
    } catch (_) {
      // A dropped command is not worth interrupting a set for; the next
      // notification will show whether it landed.
    }
  }

  @override
  Future<void> setExercise(int firmwareProfile) {
    _exerciseId = firmwareProfile;
    return _send([kCmdSetExercise, firmwareProfile]);
  }

  @override
  Future<void> resetCount() => _send([kCmdResetCount]);

  @override
  Future<void> rezero() => _send([kCmdRezero]);

  @override
  void dispose() {
    _scanTimeout?.cancel();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _stateSubscription?.cancel();
    _device?.disconnect();
    super.dispose();
  }
}

/// Fake board: finds itself after a moment, calibrates after a second of
/// "stillness", then does a set of 8–12 reps and waits for the next reset.
class SimulatedSensorService extends SensorService {
  SimulatedSensorService({Random? random}) : _random = random ?? Random();

  final Random _random;
  SensorStatus _status = SensorStatus.idle;
  DeviceState _state = DeviceState.empty;
  Timer? _pending;
  Timer? _ticker;

  int _exerciseId = 0;
  bool _calibrated = false;
  int _reps = 0;
  int _repsThisSet = 10;
  double _phase = 0;
  bool _up = false;
  double? _velocity;

  static const _tick = Duration(milliseconds: 50);
  static const _repSeconds = 2.4;
  static const _threshold = 70.0;

  @override
  SensorStatus get status => _status;
  @override
  SensorFailure? get failure => null;
  @override
  String get detail => '';
  @override
  DeviceState get state => _state;

  @override
  Future<void> connect() async {
    if (busy || connected) return;
    _status = SensorStatus.scanning;
    notifyListeners();
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 1500), () {
      _status = SensorStatus.ready;
      _ticker ??= Timer.periodic(_tick, (_) => _step());
      _startCalibration();
    });
  }

  @override
  Future<void> cancel() async {
    _pending?.cancel();
    _ticker?.cancel();
    _ticker = null;
    _status = SensorStatus.idle;
    notifyListeners();
  }

  void _startCalibration() {
    _calibrated = false;
    _phase = 0;
    _publish(0);
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 1600), () {
      _calibrated = true;
      _publish(0);
    });
  }

  void _step() {
    final finished = _reps >= _repsThisSet;
    if (!_calibrated || (finished && _phase == 0)) return;
    _phase += _tick.inMilliseconds / 1000 / _repSeconds;
    // After the last rep, finish lowering and then stay at rest.
    if (finished && _phase - _phase.floor() < 0.03) {
      _phase = 0;
      _publish(0);
      return;
    }
    final angle = 43 - 43 * cos(2 * pi * _phase);
    if (!_up && angle >= _threshold) {
      _up = true;
      _reps++;
      _velocity = 0.40 + _random.nextDouble() * 0.12;
    } else if (_up && angle < _threshold - 10) {
      _up = false;
    }
    _publish(angle);
  }

  void _publish(double angle) {
    _state = DeviceState(
      repCount: _reps,
      angleDegrees: angle,
      exerciseId: _exerciseId,
      inUpPhase: _up,
      referenceCaptured: _calibrated,
      lastRepVelocity: _velocity,
    );
    notifyListeners();
  }

  @override
  Future<void> setExercise(int firmwareProfile) async {
    _exerciseId = firmwareProfile;
  }

  @override
  Future<void> resetCount() async {
    _reps = 0;
    _phase = 0;
    _up = false;
    _velocity = null;
    _repsThisSet = 8 + _random.nextInt(5);
    _publish(0);
  }

  @override
  Future<void> rezero() async {
    await resetCount();
    _startCalibration();
  }

  @override
  void dispose() {
    _pending?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
