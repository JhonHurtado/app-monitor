import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'tilt.dart';

typedef Reading = ({Vec3 v, DateTime t});
typedef SensorStream = Stream<Reading> Function(Duration period);

/// Tipos de sensor de Android relevantes (constantes de android.hardware.Sensor).
enum SensorKind {
  accelerometer(1, 'Acelerómetro', 'm/s²', 'Aceleración propia, incluye gravedad. Base de la inclinación.'),
  linearAcceleration(10, 'Aceleración lineal', 'm/s²', 'Aceleración sin gravedad (sensor virtual). Mide movimiento.'),
  gravity(9, 'Gravedad', 'm/s²', 'Sensor virtual. La app estima la gravedad filtrando el acelerómetro.'),
  gyroscope(4, 'Giroscopio', 'rad/s', 'Velocidad angular. Mide rotaciones durante la sesión.'),
  magnetometer(2, 'Magnetómetro', 'µT', 'Campo magnético. No se usa para inclinación: lo perturban metales y el entorno.'),
  rotationVector(11, 'Vector de rotación', '—', 'Fusión con magnetómetro. No necesario para inclinación.'),
  pressure(6, 'Barómetro', 'hPa', 'Presión atmosférica. Sin uso en esta versión.');

  final int androidType;
  final String label, unit, role;
  const SensorKind(this.androidType, this.label, this.unit, this.role);
}

class DeviceSensor {
  final int type;
  final String name, vendor;
  final double resolution, maxRange;
  final int minDelayUs;
  const DeviceSensor(this.type, this.name, this.vendor, this.resolution,
      this.maxRange, this.minDelayUs);

  /// Frecuencia máxima que declara el fabricante (0 = sensor por eventos).
  double? get maxHz => minDelayUs > 0 ? 1e6 / minDelayUs : null;
}

/// Fuentes de datos de sensores. En producción usan sensors_plus y un canal
/// nativo; en las pruebas se sustituyen por flujos controlados.
class SensorSources {
  final SensorStream accelerometer, linearAcceleration, gyroscope, magnetometer;
  final Future<List<DeviceSensor>> Function() list;
  final Future<void> Function(bool on) keepScreenOn;

  const SensorSources({
    required this.accelerometer,
    required this.linearAcceleration,
    required this.gyroscope,
    required this.magnetometer,
    required this.list,
    required this.keepScreenOn,
  });

  static const _channel = MethodChannel('arbol_monitor/device');

  factory SensorSources.device() => SensorSources(
        accelerometer: (p) => accelerometerEventStream(samplingPeriod: p)
            .map((e) => (v: Vec3(e.x, e.y, e.z), t: e.timestamp)),
        linearAcceleration: (p) => userAccelerometerEventStream(samplingPeriod: p)
            .map((e) => (v: Vec3(e.x, e.y, e.z), t: e.timestamp)),
        gyroscope: (p) => gyroscopeEventStream(samplingPeriod: p)
            .map((e) => (v: Vec3(e.x, e.y, e.z), t: e.timestamp)),
        magnetometer: (p) => magnetometerEventStream(samplingPeriod: p)
            .map((e) => (v: Vec3(e.x, e.y, e.z), t: e.timestamp)),
        list: () async {
          final raw = await _channel.invokeListMethod<Map>('sensors') ?? [];
          return [
            for (final m in raw)
              DeviceSensor(
                m['type'] as int,
                m['name'] as String,
                m['vendor'] as String,
                (m['resolution'] as num).toDouble(),
                (m['maxRange'] as num).toDouble(),
                m['minDelayUs'] as int,
              )
          ];
        },
        keepScreenOn: (on) => _channel.invokeMethod('keepScreenOn', on),
      );

  /// Tipos de sensor presentes en el dispositivo.
  Future<Set<SensorKind>> available() async {
    final types = (await list()).map((s) => s.type).toSet();
    return SensorKind.values.where((k) => types.contains(k.androidType)).toSet();
  }
}
