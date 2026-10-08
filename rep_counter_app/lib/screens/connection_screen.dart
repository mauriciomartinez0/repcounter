import 'dart:math';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../sensor/sensor_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_shell.dart';

/// Sensor connection: "Sin conectar", "Buscando sensor", "Sensor no
/// encontrado".
///
/// Opened right after signing in it continues to the home screen once
/// connected. Opened from a sensor badge or before a workout
/// ([popOnConnect]) it closes and returns `true` instead.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, this.popOnConnect = false});

  final bool popOnConnect;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final SensorService _sensor;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _sensor = context.app.sensor;
    _sensor.addListener(_onSensor);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSensor());
  }

  @override
  void dispose() {
    _sensor.removeListener(_onSensor);
    _pulse.dispose();
    super.dispose();
  }

  void _onSensor() {
    if (!mounted || _left || !_sensor.connected) return;
    _left = true;
    tick();
    _continue(connected: true);
  }

  void _continue({required bool connected}) {
    if (widget.popOnConnect) {
      Navigator.of(context).pop(connected);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _sensor,
      builder: (context, _) {
        final c = context.colors;
        final status = _sensor.status;
        final searching = _sensor.busy || status == SensorStatus.ready;
        final failed = status == SensorStatus.failed;

        final (title, body) = switch ((searching, failed, _sensor.failure)) {
          (true, _, _) => (
              'Buscando sensor',
              'Mantenlo encendido y cerca del teléfono.',
            ),
          (_, true, SensorFailure.lost) => (
              'Se perdió la conexión',
              'Acerca el sensor al teléfono y vuelve a conectarlo.',
            ),
          (_, true, SensorFailure.unsupported) => (
              'Bluetooth no disponible',
              _sensor.detail,
            ),
          (_, true, SensorFailure.error) => (
              'No se pudo conectar',
              'Revisa que esté encendido y que el Bluetooth del teléfono '
                  'esté activo.',
            ),
          (_, true, _) => (
              'Sensor no encontrado',
              'Revisa que esté encendido y que el Bluetooth del teléfono '
                  'esté activo.',
            ),
          _ => ('Sin conectar', 'Enciende el sensor y acércalo al teléfono.'),
        };

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: Center(child: AppLabel('Sensor')),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 216,
                          child: searching
                              ? AnimatedBuilder(
                                  animation: _pulse,
                                  builder: (context, _) => CustomPaint(
                                    painter: _RingsPainter(
                                      color: c.mark,
                                      t: _pulse.value,
                                    ),
                                  ),
                                )
                              : CustomPaint(
                                  painter: _SensorCirclePainter(
                                    color: failed ? c.ink : c.control,
                                    crossed: failed,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: AppText.text(40, height: 1.1, color: c.ink),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: AppText.text(18, color: c.ink2),
                        ),
                        if (failed && _sensor.detail.isNotEmpty &&
                            _sensor.failure == SensorFailure.error) ...[
                          const SizedBox(height: 12),
                          Text(
                            _sensor.detail,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.text(13, color: c.ink3),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (searching)
                    SecondaryButton(
                      label: 'Cancelar',
                      height: 88,
                      fontSize: 24,
                      onPressed: _sensor.cancel,
                    )
                  else
                    PrimaryButton(
                      label: failed ? 'Reintentar' : 'Conectar',
                      height: 88,
                      fontSize: 24,
                      onPressed: _sensor.connect,
                    ),
                  const SizedBox(height: 8),
                  // Not in the mockups: lets someone check their history or
                  // edit routines without the sensor at hand.
                  Center(
                    child: TextAction(
                      label: widget.popOnConnect ? 'Volver' : 'Seguir sin sensor',
                      onPressed: () {
                        _left = true;
                        _continue(connected: false);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SensorCirclePainter extends CustomPainter {
  _SensorCirclePainter({required this.color, required this.crossed});

  final Color color;
  final bool crossed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, 59, paint);
    if (crossed) {
      final d = 59 * cos(pi / 4);
      canvas.drawLine(
        center + Offset(d, -d),
        center + Offset(-d, d),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SensorCirclePainter old) =>
      old.color != color || old.crossed != crossed;
}

/// Three rings; the outer two breathe while searching.
class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    void ring(double radius, double opacity) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final wave = (sin(t * 2 * pi) + 1) / 2;
    ring(107, 0.12 + 0.16 * wave);
    ring(83, 0.3 + 0.3 * (1 - wave));
    ring(59, 1);
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.color != color;
}
