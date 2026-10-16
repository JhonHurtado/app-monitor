import 'dart:math' as math;

import '../data/models.dart';
import '../sensors/tilt.dart';

/// Mínimo, máximo, media y desviación típica (Welford, una pasada).
class Stats {
  final int n;
  final double min, max, mean, std;
  const Stats(this.n, this.min, this.max, this.mean, this.std);

  static Stats? of(Iterable<double> values) {
    var n = 0;
    var mean = 0.0, m2 = 0.0;
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final v in values) {
      if (!v.isFinite) continue;
      n++;
      final d = v - mean;
      mean += d / n;
      m2 += d * (v - mean);
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    return n == 0 ? null : Stats(n, lo, hi, mean, math.sqrt(m2 / n));
  }

  Map<String, num> toJson() =>
      {'n': n, 'min': min, 'max': max, 'mean': mean, 'std': std};
  static Stats? fromJson(Object? j) {
    if (j == null) return null;
    final m = j as Map<String, dynamic>;
    double d(String k) => (m[k] as num).toDouble();
    return Stats(m['n'] as int, d('min'), d('max'), d('mean'), d('std'));
  }
}

enum Quality { buena, revisar, incompleta }

/// Resumen de una sesión. Se guarda en sessions.summary para no recorrer
/// todas las muestras al dibujar el historial (justificación de rendimiento);
/// puede recalcularse en cualquier momento desde la tabla samples.
class SessionSummary {
  final int sampleCount;
  final double activeSeconds;
  final int expectedSamples;
  final Stats? lateral, frontal, deltaRef, accMagnitude, linMagnitude, gyroMagnitude;

  /// Promedio del primer y último segundo de la sesión (grados).
  final ({double lateral, double frontal})? initial, last;

  /// Variación final respecto a la referencia (grados).
  final double? finalDeltaRef, finalDeltaLateral, finalDeltaFrontal;

  /// Eventos de movimiento (cruces del umbral configurado), null si no hay umbral.
  final int? movementEvents;
  final Quality quality;
  final List<String> issues;

  const SessionSummary({
    required this.sampleCount,
    required this.activeSeconds,
    required this.expectedSamples,
    this.lateral,
    this.frontal,
    this.deltaRef,
    this.accMagnitude,
    this.linMagnitude,
    this.gyroMagnitude,
    this.initial,
    this.last,
    this.finalDeltaRef,
    this.finalDeltaLateral,
    this.finalDeltaFrontal,
    this.movementEvents,
    required this.quality,
    required this.issues,
  });

  // Criterios de calidad de la MEDICIÓN (no del árbol).
  static const minSeconds = 10.0;
  static const minSampleRatio = 0.8;
  static const maxStdDeg = 1.0;

  static SessionSummary compute(
    List<Sample> samples, {
    required Map<String, dynamic> reference,
    required double samplingHz,
    required double activeSeconds,
    bool interrupted = false,
    double? movementThreshold,
  }) {
    final ref = Calibration.fromJson(reference);
    final refTilt = ref.tilt;
    final lin = samples
        .where((s) => s.linX != null)
        .map((s) => Vec3(s.linX!, s.linY!, s.linZ!).norm)
        .toList();
    final gyro = samples
        .where((s) => s.gyroX != null)
        .map((s) => Vec3(s.gyroX!, s.gyroY!, s.gyroZ!).norm);

    ({double lateral, double frontal})? window(Iterable<Sample> w) {
      final l = Stats.of(w.map((s) => s.inclLateral));
      final f = Stats.of(w.map((s) => s.inclFrontal));
      return l == null || f == null ? null : (lateral: l.mean, frontal: f.mean);
    }

    final first = samples.isEmpty ? null : samples.first.t;
    final end = samples.isEmpty ? null : samples.last.t;
    final initial = window(samples.takeWhile(
        (s) => s.t.difference(first!).inMilliseconds <= 1000));
    final last = window(samples.reversed
        .takeWhile((s) => end!.difference(s.t).inMilliseconds <= 1000));

    final lateral = Stats.of(samples.map((s) => s.inclLateral));
    final frontal = Stats.of(samples.map((s) => s.inclFrontal));
    final expected = (activeSeconds * samplingHz).round();

    int? events;
    if (movementThreshold != null && lin.isNotEmpty) {
      events = 0;
      var above = false;
      for (final m in lin) {
        if (m >= movementThreshold && !above) events = events! + 1;
        above = m >= movementThreshold;
      }
    }

    final issues = <String>[];
    if (interrupted) issues.add('Sesión interrumpida o no finalizada');
    if (samples.isEmpty) issues.add('Sin muestras registradas');
    if (activeSeconds < minSeconds) {
      issues.add('Duración activa menor a ${fmt(minSeconds, 0)} s');
    }
    if (expected > 0 && samples.length < expected * minSampleRatio) {
      issues.add(
          'Muestras recibidas: ${fmt(100 * samples.length / expected, 0)} % de lo esperado');
    }
    final maxStd = math.max(lateral?.std ?? 0, frontal?.std ?? 0);
    if (maxStd > maxStdDeg) {
      issues.add(
          'Lecturas inestables (σ = ${fmt(maxStd, 2)}°): posible movimiento del teléfono o del soporte');
    }
    if (!ref.isStable) {
      issues.add(
          'Referencia tomada con el teléfono en movimiento (σ = ${fmt(ref.stdDeg, 2)}°)');
    }
    if (lateral != null &&
        frontal != null &&
        Tilt.fromGravity(gravityDirection(lateral.mean, frontal.mean)).offAxis) {
      issues.add(
          'Teléfono lejos de la posición vertical: los ejes lateral/frontal son poco fiables');
    }

    return SessionSummary(
      sampleCount: samples.length,
      activeSeconds: activeSeconds,
      expectedSamples: expected,
      lateral: lateral,
      frontal: frontal,
      deltaRef: Stats.of(samples.map((s) => angleBetween(
          gravityDirection(s.inclLateral, s.inclFrontal), ref.gravity))),
      accMagnitude:
          Stats.of(samples.map((s) => Vec3(s.accX, s.accY, s.accZ).norm)),
      linMagnitude: Stats.of(lin),
      gyroMagnitude: Stats.of(gyro),
      initial: initial,
      last: last,
      finalDeltaRef: last == null
          ? null
          : angleBetween(
              gravityDirection(last.lateral, last.frontal), ref.gravity),
      finalDeltaLateral: last == null ? null : last.lateral - refTilt.lateral,
      finalDeltaFrontal: last == null ? null : last.frontal - refTilt.frontal,
      movementEvents: events,
      quality: interrupted || samples.isEmpty
          ? Quality.incompleta
          : issues.isEmpty
              ? Quality.buena
              : Quality.revisar,
      issues: issues,
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, double>? lf(({double lateral, double frontal})? v) =>
        v == null ? null : {'lateral': v.lateral, 'frontal': v.frontal};
    return {
      'sampleCount': sampleCount,
      'activeSeconds': activeSeconds,
      'expectedSamples': expectedSamples,
      'lateralDeg': lateral?.toJson(),
      'frontalDeg': frontal?.toJson(),
      'deltaRefDeg': deltaRef?.toJson(),
      'accMagnitudeMs2': accMagnitude?.toJson(),
      'linMagnitudeMs2': linMagnitude?.toJson(),
      'gyroMagnitudeRads': gyroMagnitude?.toJson(),
      'initialDeg': lf(initial),
      'finalDeg': lf(last),
      'finalDeltaRefDeg': finalDeltaRef,
      'finalDeltaLateralDeg': finalDeltaLateral,
      'finalDeltaFrontalDeg': finalDeltaFrontal,
      'movementEvents': movementEvents,
      'quality': quality.name,
      'issues': issues,
    };
  }

  factory SessionSummary.fromJson(Map<String, dynamic> j) {
    ({double lateral, double frontal})? lf(Object? v) {
      if (v == null) return null;
      final m = v as Map<String, dynamic>;
      return (
        lateral: (m['lateral'] as num).toDouble(),
        frontal: (m['frontal'] as num).toDouble()
      );
    }

    double? d(String k) => (j[k] as num?)?.toDouble();
    return SessionSummary(
      sampleCount: j['sampleCount'] as int,
      activeSeconds: d('activeSeconds')!,
      expectedSamples: j['expectedSamples'] as int,
      lateral: Stats.fromJson(j['lateralDeg']),
      frontal: Stats.fromJson(j['frontalDeg']),
      deltaRef: Stats.fromJson(j['deltaRefDeg']),
      accMagnitude: Stats.fromJson(j['accMagnitudeMs2']),
      linMagnitude: Stats.fromJson(j['linMagnitudeMs2']),
      gyroMagnitude: Stats.fromJson(j['gyroMagnitudeRads']),
      initial: lf(j['initialDeg']),
      last: lf(j['finalDeg']),
      finalDeltaRef: d('finalDeltaRefDeg'),
      finalDeltaLateral: d('finalDeltaLateralDeg'),
      finalDeltaFrontal: d('finalDeltaFrontalDeg'),
      movementEvents: j['movementEvents'] as int?,
      quality: Quality.values.byName(j['quality'] as String),
      issues: (j['issues'] as List).cast<String>(),
    );
  }

  static SessionSummary? ofSession(Session s) =>
      s.summary == null ? null : SessionSummary.fromJson(s.summary!);
}
