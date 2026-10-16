import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/repo.dart';
import 'device.dart';
import 'tilt.dart';

/// Frecuencias de muestreo ofrecidas. 50 Hz es más que suficiente para la
/// oscilación de un árbol (< 5 Hz) y limita el consumo de batería.
const samplingOptions = [10.0, 20.0, 50.0];

Duration periodFor(double hz) => Duration(microseconds: (1e6 / hz).round());

/// Promedia el acelerómetro durante [duration] para fijar la referencia.
Future<Calibration?> calibrate(SensorSources src,
    {Duration duration = const Duration(seconds: 2), double hz = 50}) async {
  final readings = <Vec3>[];
  final sub = src.accelerometer(periodFor(hz)).listen((r) => readings.add(r.v));
  try {
    await Future<void>.delayed(duration);
  } finally {
    unawaited(sub.cancel());
  }
  return Calibration.fromReadings(readings, DateTime.now());
}

class LiveReading {
  final Vec3 acc, gravity;
  final Vec3? lin, gyro;
  final Tilt tilt;
  final double deltaRef, deltaLateral, deltaFrontal;
  const LiveReading(this.acc, this.gravity, this.lin, this.gyro, this.tilt,
      this.deltaRef, this.deltaLateral, this.deltaFrontal);
}

enum RecState { paused, recording, finished }

/// Graba una sesión: escucha los sensores mientras está activa, agrupa las
/// muestras en memoria y las escribe por lotes cada segundo. Al pausar o
/// finalizar se detienen las suscripciones (ahorro de batería) y se vacía
/// el búfer, de modo que nunca se pierde más de ~1 s de datos.
class SessionRecorder extends ChangeNotifier {
  final Repo repo;
  final int sessionId;
  final Calibration reference;
  final double hz;
  final SensorSources src;
  final bool useLinear, useGyro;

  SessionRecorder({
    required this.repo,
    required this.sessionId,
    required this.reference,
    required this.hz,
    required this.src,
    this.useLinear = true,
    this.useGyro = true,
    Duration previouslyActive = Duration.zero,
  }) : _active = previouslyActive;

  static const chartWindow = Duration(seconds: 30);
  static const stallAfter = Duration(seconds: 3);

  final _filter = GravityFilter();
  final _buffer = <Sample>[];
  final recent = <({DateTime t, double dLateral, double dFrontal, double lin})>[];
  final _subs = <StreamSubscription>[];
  Timer? _tick;
  Vec3? _lin, _gyro;
  DateTime? _segmentStart, _lastSample, _lastNotify, _lastStored;
  Duration _active;
  bool _flushing = false, _disposed = false;

  RecState state = RecState.paused;
  LiveReading? live;
  int saved = 0, invalid = 0;
  double peakLin = 0;
  String? error, warning;

  Duration get active => _segmentStart == null
      ? _active
      : _active + DateTime.now().difference(_segmentStart!);
  int get pending => _buffer.length;

  Future<void> start() async {
    if (state != RecState.paused) return;
    error = warning = null;
    _filter.reset();
    _lastStored = null;
    final period = periodFor(hz);
    _subs.add(src.accelerometer(period).listen(_onAcc,
        onError: (Object e) => _fail('Error del acelerómetro: $e'),
        onDone: () => _fail('El acelerómetro dejó de enviar datos.')));
    if (useLinear) {
      _subs.add(src.linearAcceleration(period).listen((r) => _lin = r.v,
          onError: (Object _) {
        _lin = null;
        warning = 'Aceleración lineal no disponible; se continúa sin ella.';
      }));
    }
    if (useGyro) {
      _subs.add(src.gyroscope(period).listen((r) => _gyro = r.v,
          onError: (Object _) {
        _gyro = null;
        warning = 'Giroscopio no disponible; se continúa sin él.';
      }));
    }
    _segmentStart = _lastSample = DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    state = RecState.recording;
    await repo.setSessionStatus(sessionId, SessionStatus.running);
    notifyListeners();
  }

  void _onAcc(Reading r) {
    if (state != RecState.recording) return;
    final g = _filter.add(r.v, r.t);
    if (g == null) {
      invalid++;
      return;
    }
    // Android trata el periodo como una sugerencia y suele entregar más
    // lecturas de las pedidas: todas alimentan el filtro, pero solo se guardan
    // las que respetan la frecuencia elegida (tolerancia del 10 %).
    final last = _lastStored;
    if (last != null && r.t.difference(last) < periodFor(hz) * 0.9) return;
    _lastStored = r.t;
    final tilt = Tilt.fromGravity(g);
    final ref = reference.tilt;
    final lin = _lin, gyro = _gyro;
    _buffer.add(Sample(
      t: r.t,
      accX: r.v.x, accY: r.v.y, accZ: r.v.z,
      linX: lin?.x, linY: lin?.y, linZ: lin?.z,
      gyroX: gyro?.x, gyroY: gyro?.y, gyroZ: gyro?.z,
      inclLateral: tilt.lateral,
      inclFrontal: tilt.frontal,
    ));
    _lastSample = DateTime.now();
    live = LiveReading(r.v, g, lin, gyro, tilt, angleBetween(g, reference.gravity),
        tilt.lateral - ref.lateral, tilt.frontal - ref.frontal);
    if (lin != null && lin.norm > peakLin) peakLin = lin.norm;
    recent.add((
      t: r.t,
      dLateral: live!.deltaLateral,
      dFrontal: live!.deltaFrontal,
      lin: lin?.norm ?? 0
    ));
    while (recent.isNotEmpty && r.t.difference(recent.first.t) > chartWindow) {
      recent.removeAt(0);
    }
    // Refrescar la interfaz a ~10 Hz como máximo, aunque se muestree a 50 Hz.
    final now = DateTime.now();
    if (_lastNotify == null ||
        now.difference(_lastNotify!) > const Duration(milliseconds: 100)) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  Future<void> _onTick() async {
    await flush();
    if (state == RecState.recording &&
        DateTime.now().difference(_lastSample!) > stallAfter) {
      warning = 'Sin datos del acelerómetro en los últimos '
          '${stallAfter.inSeconds} s.';
    }
    notifyListeners();
  }

  Future<void> flush() async {
    if (_buffer.isEmpty || _flushing) return;
    _flushing = true;
    final batch = List.of(_buffer);
    _buffer.clear();
    try {
      await repo.insertSamples(sessionId, batch);
      saved += batch.length;
    } catch (e) {
      _buffer.insertAll(0, batch); // se reintenta en el siguiente lote
      error = 'Error al guardar muestras: $e';
    } finally {
      _flushing = false;
    }
  }

  Future<void> _stopListening() async {
    _tick?.cancel();
    _tick = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    if (_segmentStart != null) {
      _active += DateTime.now().difference(_segmentStart!);
      _segmentStart = null;
    }
  }

  Future<void> pause() async {
    if (state != RecState.recording) return;
    state = RecState.paused;
    await _stopListening();
    await flush();
    await repo.setSessionStatus(sessionId, SessionStatus.paused);
    notifyListeners();
  }

  Future<void> finish({String? notes}) async {
    if (state == RecState.finished) return;
    state = RecState.finished;
    await _stopListening();
    while (_flushing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await flush();
    await repo.closeSession(sessionId, SessionStatus.completed,
        endedAt: DateTime.now(),
        activeSeconds: _active.inMilliseconds / 1000,
        notes: notes);
    notifyListeners();
  }

  void _fail(String msg) {
    error = msg;
    pause();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    // Salir de la pantalla sin finalizar deja la sesión en pausa, con sus
    // datos guardados, para reanudarla o finalizarla desde el historial.
    if (state == RecState.recording) pause();
    _disposed = true;
    super.dispose();
  }
}
