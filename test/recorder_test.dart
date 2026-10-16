import 'package:arbol_monitor/analysis/summary.dart';
import 'package:arbol_monitor/data/models.dart';
import 'package:arbol_monitor/data/repo.dart';
import 'package:arbol_monitor/sensors/recorder.dart';
import 'package:arbol_monitor/sensors/tilt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late Repo repo;
  late FakeSensors fake;
  late int sessionId;

  setUp(() async {
    repo = await memoryRepo();
    fake = FakeSensors();
    final tree = await addTree(repo);
    sessionId = await repo.createSession(Session(
        treeId: tree, startedAt: DateTime.now(), samplingHz: 20,
        calibration: vertical().toJson()));
  });
  tearDown(() => repo.db.close());

  SessionRecorder recorder() => SessionRecorder(
      repo: repo, sessionId: sessionId, reference: vertical(), hz: 20, src: fake.sources);

  Future<void> emit(int n, double lateral, {DateTime? from}) async {
    final t0 = from ?? DateTime.now();
    for (var i = 0; i < n; i++) {
      fake.lin.add((v: const Vec3(0.1, 0, 0), t: t0));
      fake.gyro.add((v: const Vec3(0, 0, 0.02), t: t0));
      fake.acc.add(leaning(lateral, t0.add(Duration(milliseconds: i * 50))));
    }
    await Future<void>.delayed(Duration.zero);
  }

  test('graba, agrupa por lotes y calcula la variación respecto a la referencia', () async {
    final r = recorder();
    await r.start();
    expect(r.state, RecState.recording);
    expect((await repo.session(sessionId))!.status, SessionStatus.running);
    await emit(40, 2);
    expect(r.pending, 40, reason: 'aún en memoria, sin escribir una por una');
    expect(await repo.sampleCount(sessionId), 0);
    expect(r.live!.deltaLateral, closeTo(2, 1e-6));
    expect(r.live!.deltaRef, closeTo(2, 1e-6));
    expect(r.live!.lin!.x, 0.1);
    await r.flush();
    expect(await repo.sampleCount(sessionId), 40);
    final stored = await repo.samples(sessionId);
    expect(stored.first.gyroZ, 0.02);
    expect(stored.first.linX, 0.1);
    await r.pause();
    r.dispose();
  });

  test('pausar detiene la escucha, guarda y permite reanudar', () async {
    final r = recorder();
    await r.start();
    await emit(10, 0);
    await r.pause();
    expect(r.state, RecState.paused);
    expect(fake.acc.hasListener, isFalse, reason: 'sensores liberados en pausa');
    expect(await repo.sampleCount(sessionId), 10);
    expect((await repo.session(sessionId))!.status, SessionStatus.paused);
    await emit(10, 0); // ignoradas: no hay suscripción
    await r.start();
    await emit(5, 0);
    await r.finish(notes: 'fin');
    expect(await repo.sampleCount(sessionId), 15);
    final s = (await repo.session(sessionId))!;
    expect(s.status, SessionStatus.completed);
    expect(s.notes, 'fin');
    expect(SessionSummary.ofSession(s)!.sampleCount, 15);
    expect(fake.acc.hasListener, isFalse);
  });

  test('salir sin finalizar deja la sesión en pausa con sus datos', () async {
    final r = recorder();
    await r.start();
    await emit(12, 1);
    r.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await repo.sampleCount(sessionId), 12);
    expect((await repo.session(sessionId))!.status, SessionStatus.paused);
  });

  test('error del acelerómetro (sensor no disponible) pausa sin perder datos', () async {
    final r = recorder();
    await r.start();
    await emit(8, 0);
    fake.acc.addError(Exception('NO_SENSOR'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(r.error, contains('NO_SENSOR'));
    expect(r.state, RecState.paused);
    expect(await repo.sampleCount(sessionId), 8);
  });

  test('sensores opcionales ausentes: continúa solo con el acelerómetro', () async {
    final r = recorder();
    await r.start();
    fake.gyro.addError(Exception('NO_SENSOR'));
    await Future<void>.delayed(Duration.zero);
    expect(r.warning, contains('Giroscopio'));
    final t0 = DateTime.now();
    fake.acc.add(leaning(0, t0));
    await Future<void>.delayed(Duration.zero);
    expect(r.state, RecState.recording);
    expect(r.pending, 1);
    await r.pause();
    r.dispose();
  });

  test('guarda a la frecuencia elegida aunque el sensor entregue más rápido', () async {
    final r = recorder(); // 20 Hz = una muestra cada 50 ms
    await r.start();
    final t0 = DateTime(2026, 6, 1);
    for (var i = 0; i < 100; i++) {
      fake.acc.add(leaning(0, t0.add(Duration(milliseconds: i * 10)))); // 100 Hz
    }
    await Future<void>.delayed(Duration.zero);
    expect(r.pending, 20, reason: '1 s a 100 Hz → 20 muestras a 20 Hz');
    await r.pause();
    r.dispose();
  });

  test('descarta lecturas inválidas', () async {
    final r = recorder();
    await r.start();
    fake.acc.add((v: const Vec3(double.nan, 1, 0), t: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    expect(r.invalid, 1);
    expect(r.pending, 0);
    await r.pause();
    r.dispose();
  });

  test('calibrate promedia el acelerómetro', () async {
    final future = calibrate(fake.sources, duration: const Duration(milliseconds: 30));
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 10; i++) {
      fake.acc.add(leaning(3, DateTime.now()));
    }
    final c = (await future)!;
    expect(c.samples, 10);
    expect(c.tilt.lateral, closeTo(3, 1e-9));
    expect(fake.acc.hasListener, isFalse);
  });
}
