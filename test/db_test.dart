import 'package:arbol_monitor/analysis/summary.dart';
import 'package:arbol_monitor/data/db.dart';
import 'package:arbol_monitor/data/models.dart';
import 'package:arbol_monitor/data/repo.dart';
import 'package:arbol_monitor/sensors/tilt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

Sample s(DateTime t, [double lateral = 0]) => Sample(
    t: t, accX: 0, accY: standardGravity, accZ: 0,
    inclLateral: lateral, inclFrontal: 0);

Future<int> newSession(Repo repo, int treeId, {DateTime? at}) => repo.createSession(Session(
    treeId: treeId,
    startedAt: at ?? DateTime(2026, 4, 1, 10),
    samplingHz: 20,
    calibration: vertical().toJson(),
    sensors: ['accelerometer']));

void main() {
  late Repo repo;
  setUp(() async => repo = await memoryRepo());
  tearDown(() => repo.db.close());

  group('árboles', () {
    test('crear, editar, buscar y archivar', () async {
      final id = await repo.saveTree(Tree(
          code: 'Roble-01', species: 'Quercus', heightM: 12.5,
          photos: ['/a.jpg'], createdAt: DateTime(2026, 1, 2)));
      await addTree(repo, 'Pino-02');
      expect((await repo.trees()).map((t) => t.code), ['Pino-02', 'Roble-01']);
      expect((await repo.trees(query: 'querc')).single.id, id);

      final t = (await repo.tree(id))!;
      expect(t.photos, ['/a.jpg']);
      expect(t.heightM, 12.5);
      await repo.saveTree(Tree(id: id, code: 'Roble-01b', createdAt: t.createdAt));
      expect((await repo.tree(id))!.code, 'Roble-01b');

      await repo.setArchived(id, true);
      expect((await repo.trees()).single.code, 'Pino-02');
      expect((await repo.trees(archived: true)).single.id, id);
      await repo.setArchived(id, false);
      expect(await repo.trees(), hasLength(2));
    });

    test('restricciones de integridad', () async {
      expect(() => repo.saveTree(Tree(code: '  ', createdAt: DateTime(2026))),
          throwsA(isA<DatabaseException>()));
      expect(() => repo.saveTree(Tree(code: 'x', latitude: 95, createdAt: DateTime(2026))),
          throwsA(isA<DatabaseException>()));
      expect(() => repo.saveTree(Tree(code: 'x', heightM: -1, createdAt: DateTime(2026))),
          throwsA(isA<DatabaseException>()));
    });
  });

  group('sesiones e historial', () {
    test('las claves foráneas están activas', () async {
      expect(() => newSession(repo, 999), throwsA(isA<DatabaseException>()));
      final tree = await addTree(repo);
      await newSession(repo, tree);
      // Un árbol con sesiones no se puede borrar (se archiva).
      expect(() => repo.db.delete('trees', where: 'id = ?', whereArgs: [tree]),
          throwsA(isA<DatabaseException>()));
    });

    test('persistencia por lotes y cierre con resumen', () async {
      final tree = await addTree(repo);
      final id = await newSession(repo, tree);
      final t0 = DateTime(2026, 4, 1, 10);
      for (var b = 0; b < 4; b++) {
        await repo.insertSamples(id, [
          for (var i = 0; i < 50; i++)
            s(t0.add(Duration(milliseconds: (b * 50 + i) * 50)), 1.0)
        ]);
      }
      expect(await repo.sampleCount(id), 200);
      await repo.closeSession(id, SessionStatus.completed,
          endedAt: t0.add(const Duration(seconds: 10)), activeSeconds: 10, notes: 'ok');
      final sess = (await repo.session(id))!;
      expect(sess.status, SessionStatus.completed);
      expect(sess.duration, const Duration(seconds: 10));
      expect(sess.notes, 'ok');
      final sum = SessionSummary.ofSession(sess)!;
      expect(sum.sampleCount, 200);
      expect(sum.finalDeltaLateral, closeTo(1, 1e-9));
      expect(sum.quality, Quality.buena, reason: sum.issues.join());
    });

    test('filtros por árbol, fechas e incompletas', () async {
      final a = await addTree(repo, 'A'), b = await addTree(repo, 'B');
      final s1 = await newSession(repo, a, at: DateTime(2026, 1, 10));
      await newSession(repo, a, at: DateTime(2026, 2, 10));
      await newSession(repo, b, at: DateTime(2026, 2, 15));
      await repo.closeSession(s1, SessionStatus.completed);
      expect(await repo.sessions(treeId: a), hasLength(2));
      expect(await repo.sessions(from: DateTime(2026, 2, 1)), hasLength(2));
      expect(await repo.sessions(from: DateTime(2026, 2, 1), to: DateTime(2026, 2, 12)), hasLength(1));
      expect(await repo.sessions(onlyIncomplete: true), hasLength(2));
      expect((await repo.sessions()).first.startedAt, DateTime(2026, 2, 15), reason: 'más reciente primero');
    });

    test('borrar una sesión elimina sus muestras (cascada)', () async {
      final tree = await addTree(repo);
      final id = await newSession(repo, tree);
      await repo.insertSamples(id, [s(DateTime(2026, 4, 1, 10))]);
      await repo.deleteSession(id);
      expect(await repo.session(id), isNull);
      expect(await repo.sampleCount(id), 0);
      expect((await repo.db.query('samples')), isEmpty);
    });

    test('recupera sesiones interrumpidas conservando las muestras', () async {
      final tree = await addTree(repo);
      final running = await newSession(repo, tree);
      final paused = await newSession(repo, tree);
      await repo.setSessionStatus(paused, SessionStatus.paused);
      final t0 = DateTime(2026, 4, 1, 10);
      await repo.insertSamples(running, [
        for (var i = 0; i < 40; i++) s(t0.add(Duration(milliseconds: i * 50)))
      ]);
      expect(await repo.recoverInterrupted(), 1);
      final r = (await repo.session(running))!;
      expect(r.status, SessionStatus.interrupted);
      expect(r.incomplete, isTrue);
      expect(SessionSummary.ofSession(r)!.sampleCount, 40);
      expect(SessionSummary.ofSession(r)!.quality, Quality.incompleta);
      expect((await repo.session(paused))!.status, SessionStatus.paused,
          reason: 'las pausadas se pueden reanudar');
    });

    test('las fechas se guardan como ms epoch', () async {
      final tree = await addTree(repo);
      final id = await newSession(repo, tree, at: DateTime.utc(2026, 4, 1, 10));
      final row = (await repo.db.query('sessions', where: 'id = ?', whereArgs: [id])).single;
      expect(row['started_at'], DateTime.utc(2026, 4, 1, 10).millisecondsSinceEpoch);
    });
  });

  test('inspecciones y ajustes', () async {
    final tree = await addTree(repo);
    final id = await repo.saveInspection(Inspection(
        treeId: tree, createdAt: DateTime(2026, 5, 1),
        leafCondition: 'Normal', photos: ['/p.jpg']));
    expect((await repo.inspections(tree)).single.photos, ['/p.jpg']);
    await repo.deleteInspection(id);
    expect(await repo.inspections(tree), isEmpty);

    expect((await repo.alertSettings()).angleChangeDeg, isNull, reason: 'desactivado por defecto');
    await repo.saveAlertSettings(const AlertSettings(angleChangeDeg: 2));
    await repo.saveAlertSettings(const AlertSettings(angleChangeDeg: 3, movementMs2: 1));
    final cfg = await repo.alertSettings();
    expect(cfg.angleChangeDeg, 3);
    expect(cfg.movementMs2, 1);
    expect(cfg.sessionDiffDeg, isNull);
  });

  group('migraciones', () {
    test('base nueva queda en la última versión', () async {
      expect(await repo.db.getVersion(), kMigrations.length);
    });

    test('actualizar aplica solo los pasos pendientes y conserva datos', () async {
      final path = '${(await databaseFactoryFfiNoIsolate.getDatabasesPath())}/migr_${DateTime.now().microsecondsSinceEpoch}.db';
      final v1 = await openAppDatabase(path, factory: databaseFactoryFfiNoIsolate);
      await Repo(v1).saveTree(Tree(code: 'Antiguo', createdAt: DateTime(2025)));
      await v1.close();

      final v2 = await openAppDatabase(path,
          factory: databaseFactoryFfiNoIsolate,
          migrations: [
            ...kMigrations,
            ['ALTER TABLE trees ADD COLUMN tag TEXT'],
          ]);
      expect(await v2.getVersion(), kMigrations.length + 1);
      final row = (await v2.query('trees')).single;
      expect(row['code'], 'Antiguo');
      expect(row.containsKey('tag'), isTrue);
      await v2.close();
      await databaseFactoryFfiNoIsolate.deleteDatabase(path);
    });
  });
}
