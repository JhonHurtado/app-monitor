import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'repo.dart';

/// CSV con separador coma, punto decimal y fechas ISO 8601 UTC, para que
/// sea legible por hojas de cálculo y herramientas de análisis.
String _cell(Object? v) {
  if (v == null) return '';
  final s = v is DateTime ? v.toUtc().toIso8601String() : '$v';
  return s.contains(RegExp('[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String _csv(List<String> header, Iterable<List<Object?>> rows) =>
    '${[header, ...rows].map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';

String sessionsCsv(List<Session> sessions, Map<int, Tree> trees) {
  double? n(Map? m, String k) => (m?[k] as num?)?.toDouble();
  return _csv([
    'session_id', 'tree_id', 'tree_code', 'started_at_utc', 'ended_at_utc',
    'duration_s', 'sampling_hz', 'status', 'quality', 'sample_count',
    'initial_lateral_deg', 'initial_frontal_deg',
    'final_lateral_deg', 'final_frontal_deg', 'final_delta_ref_deg',
    'lateral_min_deg', 'lateral_max_deg', 'lateral_mean_deg',
    'frontal_min_deg', 'frontal_max_deg', 'frontal_mean_deg',
    'lin_accel_max_ms2', 'gyro_max_rads',
    'ref_lateral_deg', 'ref_frontal_deg', 'sensors', 'conditions', 'notes',
  ], sessions.map((s) {
    final m = s.summary;
    return [
      s.id, s.treeId, trees[s.treeId]?.code, s.startedAt, s.endedAt,
      s.duration == null ? null : s.duration!.inMilliseconds / 1000,
      s.samplingHz, s.status.name, m?['quality'], m?['sampleCount'],
      n(m?['initialDeg'], 'lateral'), n(m?['initialDeg'], 'frontal'),
      n(m?['finalDeg'], 'lateral'), n(m?['finalDeg'], 'frontal'),
      m?['finalDeltaRefDeg'],
      n(m?['lateralDeg'], 'min'), n(m?['lateralDeg'], 'max'), n(m?['lateralDeg'], 'mean'),
      n(m?['frontalDeg'], 'min'), n(m?['frontalDeg'], 'max'), n(m?['frontalDeg'], 'mean'),
      n(m?['linMagnitudeMs2'], 'max'), n(m?['gyroMagnitudeRads'], 'max'),
      s.calibration['lateralDeg'], s.calibration['frontalDeg'],
      s.sensors.join(' '), jsonEncode(s.conditions), s.notes,
    ];
  }));
}

String samplesCsv(Map<int, List<Sample>> bySession) => _csv([
      'session_id', 'timestamp_utc', 'acc_x_ms2', 'acc_y_ms2', 'acc_z_ms2',
      'lin_x_ms2', 'lin_y_ms2', 'lin_z_ms2',
      'gyro_x_rads', 'gyro_y_rads', 'gyro_z_rads',
      'incl_lateral_deg', 'incl_frontal_deg',
    ], [
      for (final e in bySession.entries)
        for (final s in e.value)
          [
            e.key, s.t, s.accX, s.accY, s.accZ, s.linX, s.linY, s.linZ,
            s.gyroX, s.gyroY, s.gyroZ, s.inclLateral, s.inclFrontal,
          ]
    ]);

String exportJson({
  required List<Tree> trees,
  required List<Session> sessions,
  required Map<int, List<Sample>> samples,
  required List<Inspection> inspections,
}) {
  Map<String, Object?> clean(Map<String, Object?> row) => {
        for (final e in row.entries)
          e.key: e.value is String &&
                  (e.key == 'photos' ||
                      e.key == 'calibration' ||
                      e.key == 'conditions' ||
                      e.key == 'sensors' ||
                      e.key == 'summary')
              ? jsonDecode(e.value as String)
              : e.value,
      };
  return const JsonEncoder.withIndent('  ').convert({
    'format': 'arbol_monitor/1',
    'units': {
      'time': 'ms desde epoch UTC',
      'acceleration': 'm/s²',
      'angular_velocity': 'rad/s',
      'inclination': 'grados',
      'height': 'm',
      'trunk_diameter': 'cm',
    },
    'coordinate_system':
        'Android: x derecha de la pantalla, y parte superior, z hacia el usuario',
    'trees': trees.map((t) => clean(t.toRow())).toList(),
    'sessions': [
      for (final s in sessions)
        {
          ...clean(s.toRow()),
          'samples': [
            for (final x in samples[s.id] ?? const <Sample>[])
              clean(x.toRow(s.id!))..remove('session_id')
          ],
        }
    ],
    'inspections': inspections.map((i) => clean(i.toRow())).toList(),
  });
}

/// Genera sesiones.csv, muestras.csv y datos.json para las sesiones dadas
/// (y sus árboles e inspecciones) y abre el diálogo de compartir de Android.
Future<void> exportAndShare(Repo repo, List<Session> sessions) async {
  final treeIds = sessions.map((s) => s.treeId).toSet();
  final trees = {
    for (final id in treeIds) id: (await repo.tree(id))!,
  };
  final samples = {
    for (final s in sessions) s.id!: await repo.samples(s.id!),
  };
  final inspections = [
    for (final id in treeIds) ...await repo.inspections(id),
  ];
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');
  final dir = Directory(p.join((await getTemporaryDirectory()).path, 'export_$stamp'));
  await dir.create(recursive: true);
  final files = {
    'sesiones.csv': sessionsCsv(sessions, trees),
    'muestras.csv': samplesCsv(samples),
    'datos.json': exportJson(
        trees: trees.values.toList(),
        sessions: sessions,
        samples: samples,
        inspections: inspections),
  };
  final paths = <XFile>[];
  for (final e in files.entries) {
    final f = File(p.join(dir.path, e.key));
    await f.writeAsString(e.value);
    paths.add(XFile(f.path));
  }
  await SharePlus.instance.share(
      ShareParams(files: paths, subject: 'Datos de monitoreo de árboles'));
}
