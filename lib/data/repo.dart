import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../analysis/summary.dart';
import 'models.dart';

/// Acceso a datos. Todas las escrituras incrementan [changes] para que las
/// pantallas abiertas se recarguen.
class Repo {
  final Database db;
  final changes = ValueNotifier(0);
  Repo(this.db);

  void _changed() => changes.value++;

  // ---- Árboles ----

  Future<List<Tree>> trees({bool archived = false, String query = ''}) async {
    final q = '%${query.trim()}%';
    final rows = await db.query('trees',
        where:
            'archived_at IS ${archived ? 'NOT ' : ''}NULL AND (code LIKE ? OR IFNULL(species, \'\') LIKE ? OR IFNULL(location, \'\') LIKE ?)',
        whereArgs: [q, q, q],
        orderBy: 'code COLLATE NOCASE');
    return rows.map(Tree.fromRow).toList();
  }

  Future<Tree?> tree(int id) async {
    final rows = await db.query('trees', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Tree.fromRow(rows.first);
  }

  Future<int> saveTree(Tree t) async {
    final row = t.toRow()..remove('id');
    final id = t.id == null
        ? await db.insert('trees', row)
        : (await db.update('trees', row, where: 'id = ?', whereArgs: [t.id]),
                t.id!)
            .$2;
    _changed();
    return id;
  }

  Future<void> setArchived(int id, bool archived) async {
    await db.update('trees',
        {'archived_at': archived ? DateTime.now().millisecondsSinceEpoch : null},
        where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  // ---- Sesiones ----

  Future<int> createSession(Session s) async {
    final id = await db.insert('sessions', s.toRow()..remove('id'));
    _changed();
    return id;
  }

  Future<Session?> session(int id) async {
    final rows = await db.query('sessions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Session.fromRow(rows.first);
  }

  Future<List<Session>> sessions(
      {int? treeId, DateTime? from, DateTime? to, bool onlyIncomplete = false}) async {
    final where = <String>[];
    final args = <Object>[];
    if (treeId != null) {
      where.add('tree_id = ?');
      args.add(treeId);
    }
    if (from != null) {
      where.add('started_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('started_at < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    if (onlyIncomplete) where.add("status != 'completed'");
    final rows = await db.query('sessions',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'started_at DESC');
    return rows.map(Session.fromRow).toList();
  }

  Future<void> setSessionStatus(int id, SessionStatus status) async {
    await db.update('sessions', {'status': status.name},
        where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> setSessionNotes(int id, String notes) async {
    await db.update('sessions', {'notes': notes},
        where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  /// Cierra la sesión: calcula el resumen a partir de las muestras guardadas.
  Future<void> closeSession(int id, SessionStatus status,
      {DateTime? endedAt, double? activeSeconds, String? notes}) async {
    final s = (await session(id))!;
    final samples = await this.samples(id);
    final end = endedAt ??
        (samples.isEmpty ? s.startedAt : samples.last.t);
    final summary = SessionSummary.compute(
      samples,
      reference: s.calibration,
      samplingHz: s.samplingHz,
      activeSeconds: activeSeconds ?? end.difference(s.startedAt).inMilliseconds / 1000,
      interrupted: status != SessionStatus.completed,
      movementThreshold: (await alertSettings()).movementMs2,
    );
    await db.update(
        'sessions',
        {
          'status': status.name,
          'ended_at': end.isBefore(s.startedAt)
              ? s.startedAt.millisecondsSinceEpoch
              : end.millisecondsSinceEpoch,
          'summary': jsonEncode(summary.toJson()),
          'notes': ?notes,
        },
        where: 'id = ?',
        whereArgs: [id]);
    _changed();
  }

  Future<void> deleteSession(int id) async {
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  /// Sesiones que quedaron abiertas porque la app se cerró o falló: se
  /// marcan como interrumpidas conservando las muestras ya guardadas.
  Future<int> recoverInterrupted() async {
    final rows = await db.query('sessions', where: "status = 'running'");
    for (final r in rows) {
      await closeSession(r['id'] as int, SessionStatus.interrupted);
    }
    return rows.length;
  }

  // ---- Muestras ----

  /// Inserta un lote de muestras en una sola transacción.
  Future<void> insertSamples(int sessionId, List<Sample> batch) async {
    if (batch.isEmpty) return;
    final b = db.batch();
    for (final s in batch) {
      b.insert('samples', s.toRow(sessionId));
    }
    await b.commit(noResult: true);
  }

  Future<List<Sample>> samples(int sessionId) async {
    final rows = await db.query('samples',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 't, id');
    return rows.map(Sample.fromRow).toList();
  }

  Future<int> sampleCount(int sessionId) async => Sqflite.firstIntValue(
          await db.rawQuery(
              'SELECT COUNT(*) FROM samples WHERE session_id = ?', [sessionId])) ??
      0;

  // ---- Inspecciones ----

  Future<List<Inspection>> inspections(int treeId) async {
    final rows = await db.query('inspections',
        where: 'tree_id = ?', whereArgs: [treeId], orderBy: 'created_at DESC');
    return rows.map(Inspection.fromRow).toList();
  }

  Future<int> saveInspection(Inspection i) async {
    final row = i.toRow()..remove('id');
    final id = i.id == null
        ? await db.insert('inspections', row)
        : (await db.update('inspections', row,
                    where: 'id = ?', whereArgs: [i.id]),
                i.id!)
            .$2;
    _changed();
    return id;
  }

  Future<void> deleteInspection(int id) async {
    await db.delete('inspections', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  // ---- Ajustes ----

  Future<AlertSettings> alertSettings() async {
    final rows =
        await db.query('settings', where: 'key = ?', whereArgs: ['alerts']);
    return rows.isEmpty
        ? const AlertSettings()
        : AlertSettings.fromJson(jsonDecode(rows.first['value'] as String));
  }

  Future<void> saveAlertSettings(AlertSettings s) async {
    await db.insert('settings', {'key': 'alerts', 'value': jsonEncode(s.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _changed();
  }
}
