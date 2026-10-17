import 'package:flutter/services.dart';

import '../sensors/tilt.dart';

/// Adaptador del modelo TFLite instalado en Android.
class AnomalyModel {
  static const windowSize = 20;
  static const samplePeriod = Duration(milliseconds: 100);
  static const anomalyThreshold = 0.85;
  static const _gravity = 9.80665;
  static const _channel = MethodChannel('arbol_monitor/model');

  static List<List<double>> prepareInput(List<Vec3> readings) {
    if (readings.length != windowSize) {
      throw ArgumentError.value(
        readings.length,
        'readings',
        'Se requieren $windowSize muestras.',
      );
    }
    return [
      for (final r in readings)
        [r.x / _gravity, r.y / _gravity, r.z / _gravity],
    ];
  }

  static Future<double> predict(List<Vec3> readings) async {
    final score = await _channel.invokeMethod<double>('classifyWindow', {
      'samples': prepareInput(readings),
    });
    if (score == null || !score.isFinite || score < 0 || score > 1) {
      throw StateError('El modelo devolvió una puntuación inválida: $score');
    }
    return score;
  }
}
