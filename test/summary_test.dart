import 'package:arbol_monitor/analysis/alerts.dart';
import 'package:arbol_monitor/analysis/summary.dart';
import 'package:arbol_monitor/data/models.dart';
import 'package:arbol_monitor/sensors/tilt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

List<Sample> series(int n, double hz, double Function(int) lateral,
    {double? lin, double? gyro}) {
  final t0 = DateTime(2026, 3, 1);
  return [
    for (var i = 0; i < n; i++)
      Sample(
        t: t0.add(Duration(microseconds: (i * 1e6 / hz).round())),
        accX: 0, accY: standardGravity, accZ: 0,
        linX: lin, linY: lin == null ? null : 0, linZ: lin == null ? null : 0,
        gyroX: gyro, gyroY: gyro == null ? null : 0, gyroZ: gyro == null ? null : 0,
        inclLateral: lateral(i),
        inclFrontal: 0,
      )
  ];
}

void main() {
  final ref = vertical().toJson();

  test('Stats: min, max, media y desviación', () {
    final s = Stats.of([2, 4, 4, 4, 5, 5, 7, 9])!;
    expect(s.n, 8);
    expect(s.min, 2);
    expect(s.max, 9);
    expect(s.mean, 5);
    expect(s.std, closeTo(2, 1e-12));
    expect(Stats.of([]), isNull);
    expect(Stats.of([double.nan, 1])!.n, 1);
  });

  test('resumen de una sesión estable y completa', () {
    // 20 s a 20 Hz: lateral pasa de 0° a 0,5°.
    final samples = series(400, 20, (i) => i < 200 ? 0 : 0.5, lin: 0.05, gyro: 0.01);
    final s = SessionSummary.compute(samples,
        reference: ref, samplingHz: 20, activeSeconds: 20);
    expect(s.sampleCount, 400);
    expect(s.initial!.lateral, closeTo(0, 1e-9));
    expect(s.last!.lateral, closeTo(0.5, 1e-9));
    expect(s.finalDeltaLateral, closeTo(0.5, 1e-9));
    expect(s.finalDeltaRef, closeTo(0.5, 1e-6));
    expect(s.lateral!.max, 0.5);
    expect(s.linMagnitude!.max, closeTo(0.05, 1e-12));
    expect(s.gyroMagnitude!.max, closeTo(0.01, 1e-12));
    expect(s.movementEvents, isNull, reason: 'sin umbral no se cuentan eventos');
    expect(s.quality, Quality.buena, reason: s.issues.join());
  });

  test('calidad: sesión corta, con huecos e inestable', () {
    final samples = series(50, 20, (i) => i.isEven ? 3 : -3);
    final s = SessionSummary.compute(samples,
        reference: ref, samplingHz: 20, activeSeconds: 8);
    expect(s.quality, Quality.revisar);
    expect(s.issues.join('\n'), contains('menor a 10 s'));
    expect(s.issues.join('\n'), contains('31 %'));
    expect(s.issues.join('\n'), contains('inestables'));
  });

  test('sesión interrumpida o vacía es incompleta', () {
    final empty = SessionSummary.compute([],
        reference: ref, samplingHz: 20, activeSeconds: 0);
    expect(empty.quality, Quality.incompleta);
    expect(empty.finalDeltaRef, isNull);
    final cut = SessionSummary.compute(series(400, 20, (_) => 0),
        reference: ref, samplingHz: 20, activeSeconds: 20, interrupted: true);
    expect(cut.quality, Quality.incompleta);
  });

  test('eventos de movimiento cuentan cruces del umbral', () {
    final samples = series(30, 20, (_) => 0)
        .asMap()
        .entries
        .map((e) => Sample(
              t: e.value.t, accX: 0, accY: standardGravity, accZ: 0,
              linX: (e.key ~/ 5).isOdd ? 2.0 : 0.1, linY: 0, linZ: 0,
              inclLateral: 0, inclFrontal: 0))
        .toList();
    final s = SessionSummary.compute(samples,
        reference: ref, samplingHz: 20, activeSeconds: 1.5, movementThreshold: 1);
    expect(s.movementEvents, 3);
  });

  test('ida y vuelta JSON del resumen', () {
    final s = SessionSummary.compute(series(400, 20, (i) => i / 400, lin: 0.1),
        reference: ref, samplingHz: 20, activeSeconds: 20, movementThreshold: 1);
    final back = SessionSummary.fromJson(s.toJson());
    expect(back.toJson(), s.toJson());
  });

  group('alertas', () {
    final s = SessionSummary.compute(series(400, 20, (_) => 2.5, lin: 0.8),
        reference: ref, samplingHz: 20, activeSeconds: 20);

    test('desactivadas por defecto', () {
      expect(sessionAlerts(s, const AlertSettings()), isEmpty);
    });

    test('describen el dato observado sin conclusiones', () {
      final a = sessionAlerts(s,
          const AlertSettings(angleChangeDeg: 2, movementMs2: 0.5));
      expect(a, hasLength(2));
      expect(a[0], startsWith('La inclinación registrada difiere 2,5° de la referencia'));
      expect(a[1], contains('0,80 m/s²'));
      for (final m in a) {
        expect(m.toLowerCase(), isNot(contains('caer')));
        expect(m.toLowerCase(), isNot(contains('riesgo')));
      }
    });

    test('no alerta por debajo del umbral', () {
      expect(sessionAlerts(s, const AlertSettings(angleChangeDeg: 3, movementMs2: 1)), isEmpty);
    });

    test('compara con la sesión anterior', () {
      final prev = SessionSummary.compute(series(400, 20, (_) => 0),
          reference: ref, samplingHz: 20, activeSeconds: 20);
      final a = sessionAlerts(s, const AlertSettings(sessionDiffDeg: 1),
          previous: prev, previousDate: DateTime(2026, 2, 3, 9, 5));
      expect(a.single, contains('difiere 2,5° de la sesión del 03/02/2026 09:05'));
      expect(a.single, contains('referencias distintas'));
      expect(
          sessionAlerts(s, const AlertSettings(sessionDiffDeg: 1),
                  previous: prev, sameReference: true)
              .single,
          isNot(contains('referencias distintas')));
    });
  });
}
