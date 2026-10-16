import 'dart:convert';

import 'package:arbol_monitor/data/export.dart';
import 'package:arbol_monitor/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final tree = Tree(id: 1, code: 'Roble, "norte"', createdAt: DateTime.utc(2026), photos: ['/x.jpg']);
  final session = Session(
    id: 5, treeId: 1,
    startedAt: DateTime.utc(2026, 3, 1, 10),
    endedAt: DateTime.utc(2026, 3, 1, 10, 1),
    samplingHz: 20,
    calibration: vertical().toJson(),
    conditions: {'wind': 'Brisa'},
    sensors: ['accelerometer', 'gyroscope'],
    status: SessionStatus.completed,
    summary: {'quality': 'buena', 'sampleCount': 2, 'finalDeg': {'lateral': 1.5, 'frontal': -0.5}},
    notes: 'línea 1\nlínea 2',
  );
  final samples = {
    5: [
      Sample(t: DateTime.utc(2026, 3, 1, 10), accX: 0.1, accY: 9.8, accZ: 0,
          gyroX: 0.01, gyroY: 0, gyroZ: 0, inclLateral: 1.5, inclFrontal: -0.5),
      Sample(t: DateTime.utc(2026, 3, 1, 10, 0, 0, 50), accX: 0.2, accY: 9.8, accZ: 0,
          inclLateral: 1.6, inclFrontal: -0.5),
    ]
  };

  test('CSV de sesiones: cabecera con unidades y escape de campos', () {
    final csv = sessionsCsv([session], {1: tree});
    final lines = csv.split('\r\n');
    expect(lines[0], startsWith('session_id,tree_id,tree_code,started_at_utc'));
    expect(lines[0], contains('final_lateral_deg'));
    expect(csv, contains('"Roble, ""norte"""'));
    expect(csv, contains('2026-03-01T10:00:00.000Z'));
    expect(csv, contains(',60.0,'), reason: 'duración en segundos');
    expect(csv, contains('"línea 1\nlínea 2"'));
    expect(csv, contains(',1.5,-0.5,'));
  });

  test('CSV de muestras: una fila por muestra, vacíos para sensores ausentes', () {
    final lines = samplesCsv(samples).trim().split('\r\n');
    expect(lines, hasLength(3));
    expect(lines[0], 'session_id,timestamp_utc,acc_x_ms2,acc_y_ms2,acc_z_ms2,'
        'lin_x_ms2,lin_y_ms2,lin_z_ms2,gyro_x_rads,gyro_y_rads,gyro_z_rads,'
        'incl_lateral_deg,incl_frontal_deg');
    expect(lines[1], '5,2026-03-01T10:00:00.000Z,0.1,9.8,0.0,,,,0.01,0.0,0.0,1.5,-0.5');
    expect(lines[2], contains(',,,,,,,1.6,'));
  });

  test('JSON: estructura anidada, unidades y campos JSON decodificados', () {
    final j = jsonDecode(exportJson(
        trees: [tree], sessions: [session], samples: samples,
        inspections: [Inspection(id: 1, treeId: 1, createdAt: DateTime.utc(2026), pests: 'No')]))
        as Map<String, dynamic>;
    expect(j['units']['inclination'], 'grados');
    expect(j['trees'][0]['photos'], ['/x.jpg']);
    final s = j['sessions'][0];
    expect(s['conditions'], {'wind': 'Brisa'});
    expect(s['summary']['quality'], 'buena');
    expect(s['calibration']['gravity']['y'], closeTo(9.80665, 1e-9));
    expect(s['samples'], hasLength(2));
    expect(s['samples'][0]['incl_lateral_deg'], 1.5);
    expect(s['samples'][0].containsKey('session_id'), isFalse);
    expect(j['inspections'][0]['pests'], 'No');
  });
}
