import 'package:sqflite/sqflite.dart';

/// Migraciones en orden. La versión de la base de datos = número de pasos.
/// Para cambiar el esquema, AÑADE un paso al final; nunca edites uno existente.
const List<List<String>> kMigrations = [
  // v1: esquema inicial
  [
    '''CREATE TABLE trees(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL CHECK(length(trim(code)) > 0),
      species TEXT,
      location TEXT,
      visual_status TEXT,
      notes TEXT,
      latitude REAL CHECK(latitude BETWEEN -90 AND 90),
      longitude REAL CHECK(longitude BETWEEN -180 AND 180),
      height_m REAL CHECK(height_m > 0),
      trunk_diameter_cm REAL CHECK(trunk_diameter_cm > 0),
      photos TEXT NOT NULL DEFAULT '[]',
      created_at INTEGER NOT NULL,
      archived_at INTEGER
    )''',
    '''CREATE TABLE sessions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tree_id INTEGER NOT NULL REFERENCES trees(id) ON DELETE RESTRICT,
      started_at INTEGER NOT NULL,
      ended_at INTEGER CHECK(ended_at IS NULL OR ended_at >= started_at),
      sampling_hz REAL NOT NULL CHECK(sampling_hz > 0),
      calibration TEXT NOT NULL,
      conditions TEXT NOT NULL DEFAULT '{}',
      sensors TEXT NOT NULL DEFAULT '[]',
      status TEXT NOT NULL
        CHECK(status IN ('running','paused','completed','interrupted')),
      summary TEXT,
      notes TEXT
    )''',
    'CREATE INDEX sessions_tree ON sessions(tree_id, started_at)',
    '''CREATE TABLE samples(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      t INTEGER NOT NULL,
      acc_x REAL NOT NULL, acc_y REAL NOT NULL, acc_z REAL NOT NULL,
      lin_x REAL, lin_y REAL, lin_z REAL,
      gyro_x REAL, gyro_y REAL, gyro_z REAL,
      incl_lateral_deg REAL NOT NULL,
      incl_frontal_deg REAL NOT NULL
    )''',
    'CREATE INDEX samples_session ON samples(session_id, t)',
    '''CREATE TABLE inspections(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tree_id INTEGER NOT NULL REFERENCES trees(id) ON DELETE RESTRICT,
      created_at INTEGER NOT NULL,
      leaf_condition TEXT,
      trunk_condition TEXT,
      branch_condition TEXT,
      crown_condition TEXT,
      pests TEXT,
      visible_inclination TEXT,
      observations TEXT,
      photos TEXT NOT NULL DEFAULT '[]'
    )''',
    'CREATE INDEX inspections_tree ON inspections(tree_id, created_at)',
    'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  ],
];

Future<Database> openAppDatabase(
  String path, {
  DatabaseFactory? factory,
  List<List<String>> migrations = kMigrations,
}) {
  Future<void> migrate(Database db, int from, int to) async {
    for (var v = from; v < to; v++) {
      for (final sql in migrations[v]) {
        await db.execute(sql);
      }
    }
  }

  return (factory ?? databaseFactory).openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: migrations.length,
      // SQLite no aplica las claves foráneas si no se activan por conexión.
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => migrate(db, 0, version),
      onUpgrade: migrate,
    ),
  );
}
