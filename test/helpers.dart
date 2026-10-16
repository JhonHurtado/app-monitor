import 'dart:async';

import 'package:arbol_monitor/data/db.dart';
import 'package:arbol_monitor/data/models.dart';
import 'package:arbol_monitor/data/repo.dart';
import 'package:arbol_monitor/sensors/device.dart';
import 'package:arbol_monitor/sensors/tilt.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Repo> memoryRepo() async => Repo(await openAppDatabase(
    inMemoryDatabasePath,
    factory: databaseFactoryFfiNoIsolate));

Future<int> addTree(Repo repo, [String code = 'A-1']) =>
    repo.saveTree(Tree(code: code, createdAt: DateTime(2026, 1, 1)));

Calibration vertical() =>
    Calibration(const Vec3(0, standardGravity, 0), 100, 0.1, DateTime(2026));

/// Fuentes de sensores controladas desde la prueba.
class FakeSensors {
  final acc = StreamController<Reading>.broadcast();
  final lin = StreamController<Reading>.broadcast();
  final gyro = StreamController<Reading>.broadcast();
  final mag = StreamController<Reading>.broadcast();
  Set<int> present;
  bool screenOn = false;
  FakeSensors({this.present = const {1, 4, 10, 2}});

  SensorSources get sources => SensorSources(
        accelerometer: (_) => acc.stream,
        linearAcceleration: (_) => lin.stream,
        gyroscope: (_) => gyro.stream,
        magnetometer: (_) => mag.stream,
        list: () async => [
          for (final t in present) DeviceSensor(t, 'Sensor $t', 'Test', 0.01, 20, 10000)
        ],
        keepScreenOn: (on) async => screenOn = on,
      );
}

/// Lectura de un teléfono vertical inclinado [lateralDeg] hacia la derecha.
Reading leaning(double lateralDeg, DateTime t) {
  final g = gravityDirection(lateralDeg, 0) * standardGravity;
  return (v: g, t: t);
}
