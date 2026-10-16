import 'dart:convert';

/// Todas las fechas se guardan como milisegundos desde epoch (UTC) en INTEGER.
int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;
DateTime? _dt(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
double? _d(Object? v) => (v as num?)?.toDouble();
List<String> _list(Object? v) =>
    v == null ? [] : (jsonDecode(v as String) as List).cast<String>();
Map<String, dynamic> _map(Object? v) =>
    v == null ? {} : jsonDecode(v as String) as Map<String, dynamic>;

class Tree {
  final int? id;
  final String code;
  final String? species, location, visualStatus, notes;
  final double? latitude, longitude, heightM, trunkDiameterCm;
  final List<String> photos;
  final DateTime createdAt;
  final DateTime? archivedAt;

  const Tree({
    this.id,
    required this.code,
    this.species,
    this.location,
    this.visualStatus,
    this.notes,
    this.latitude,
    this.longitude,
    this.heightM,
    this.trunkDiameterCm,
    this.photos = const [],
    required this.createdAt,
    this.archivedAt,
  });

  bool get archived => archivedAt != null;

  Map<String, Object?> toRow() => {
        'id': id,
        'code': code,
        'species': species,
        'location': location,
        'visual_status': visualStatus,
        'notes': notes,
        'latitude': latitude,
        'longitude': longitude,
        'height_m': heightM,
        'trunk_diameter_cm': trunkDiameterCm,
        'photos': jsonEncode(photos),
        'created_at': _ms(createdAt),
        'archived_at': _ms(archivedAt),
      };

  factory Tree.fromRow(Map<String, Object?> r) => Tree(
        id: r['id'] as int,
        code: r['code'] as String,
        species: r['species'] as String?,
        location: r['location'] as String?,
        visualStatus: r['visual_status'] as String?,
        notes: r['notes'] as String?,
        latitude: _d(r['latitude']),
        longitude: _d(r['longitude']),
        heightM: _d(r['height_m']),
        trunkDiameterCm: _d(r['trunk_diameter_cm']),
        photos: _list(r['photos']),
        createdAt: _dt(r['created_at'])!,
        archivedAt: _dt(r['archived_at']),
      );
}

enum SessionStatus { running, paused, completed, interrupted }

class Session {
  final int? id;
  final int treeId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double samplingHz;
  final Map<String, dynamic> calibration; // ver Calibration.toJson
  final Map<String, dynamic> conditions; // colocación, viento, etc.
  final List<String> sensors; // sensores utilizados
  final SessionStatus status;
  final Map<String, dynamic>? summary; // ver SessionSummary.toJson
  final String? notes;

  const Session({
    this.id,
    required this.treeId,
    required this.startedAt,
    this.endedAt,
    required this.samplingHz,
    required this.calibration,
    this.conditions = const {},
    this.sensors = const [],
    this.status = SessionStatus.running,
    this.summary,
    this.notes,
  });

  Duration? get duration => endedAt?.difference(startedAt);
  bool get incomplete =>
      status == SessionStatus.interrupted ||
      status == SessionStatus.running ||
      status == SessionStatus.paused;

  Map<String, Object?> toRow() => {
        'id': id,
        'tree_id': treeId,
        'started_at': _ms(startedAt),
        'ended_at': _ms(endedAt),
        'sampling_hz': samplingHz,
        'calibration': jsonEncode(calibration),
        'conditions': jsonEncode(conditions),
        'sensors': jsonEncode(sensors),
        'status': status.name,
        'summary': summary == null ? null : jsonEncode(summary),
        'notes': notes,
      };

  factory Session.fromRow(Map<String, Object?> r) => Session(
        id: r['id'] as int,
        treeId: r['tree_id'] as int,
        startedAt: _dt(r['started_at'])!,
        endedAt: _dt(r['ended_at']),
        samplingHz: _d(r['sampling_hz'])!,
        calibration: _map(r['calibration']),
        conditions: _map(r['conditions']),
        sensors: _list(r['sensors']),
        status: SessionStatus.values.byName(r['status'] as String),
        summary: r['summary'] == null ? null : _map(r['summary']),
        notes: r['notes'] as String?,
      );
}

/// Una lectura agrupada. Unidades: aceleración m/s², velocidad angular rad/s,
/// inclinación en grados (calculada con el filtro de gravedad).
class Sample {
  final DateTime t;
  final double accX, accY, accZ;
  final double? linX, linY, linZ; // aceleración lineal (sin gravedad), si existe
  final double? gyroX, gyroY, gyroZ;
  final double inclLateral, inclFrontal;

  const Sample({
    required this.t,
    required this.accX,
    required this.accY,
    required this.accZ,
    this.linX,
    this.linY,
    this.linZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    required this.inclLateral,
    required this.inclFrontal,
  });

  Map<String, Object?> toRow(int sessionId) => {
        'session_id': sessionId,
        't': _ms(t),
        'acc_x': accX,
        'acc_y': accY,
        'acc_z': accZ,
        'lin_x': linX,
        'lin_y': linY,
        'lin_z': linZ,
        'gyro_x': gyroX,
        'gyro_y': gyroY,
        'gyro_z': gyroZ,
        'incl_lateral_deg': inclLateral,
        'incl_frontal_deg': inclFrontal,
      };

  factory Sample.fromRow(Map<String, Object?> r) => Sample(
        t: _dt(r['t'])!,
        accX: _d(r['acc_x'])!,
        accY: _d(r['acc_y'])!,
        accZ: _d(r['acc_z'])!,
        linX: _d(r['lin_x']),
        linY: _d(r['lin_y']),
        linZ: _d(r['lin_z']),
        gyroX: _d(r['gyro_x']),
        gyroY: _d(r['gyro_y']),
        gyroZ: _d(r['gyro_z']),
        inclLateral: _d(r['incl_lateral_deg'])!,
        inclFrontal: _d(r['incl_frontal_deg'])!,
      );
}

class Inspection {
  final int? id;
  final int treeId;
  final DateTime createdAt;
  final String? leafCondition,
      trunkCondition,
      branchCondition,
      crownCondition,
      pests,
      visibleInclination,
      observations;
  final List<String> photos;

  const Inspection({
    this.id,
    required this.treeId,
    required this.createdAt,
    this.leafCondition,
    this.trunkCondition,
    this.branchCondition,
    this.crownCondition,
    this.pests,
    this.visibleInclination,
    this.observations,
    this.photos = const [],
  });

  Map<String, Object?> toRow() => {
        'id': id,
        'tree_id': treeId,
        'created_at': _ms(createdAt),
        'leaf_condition': leafCondition,
        'trunk_condition': trunkCondition,
        'branch_condition': branchCondition,
        'crown_condition': crownCondition,
        'pests': pests,
        'visible_inclination': visibleInclination,
        'observations': observations,
        'photos': jsonEncode(photos),
      };

  factory Inspection.fromRow(Map<String, Object?> r) => Inspection(
        id: r['id'] as int,
        treeId: r['tree_id'] as int,
        createdAt: _dt(r['created_at'])!,
        leafCondition: r['leaf_condition'] as String?,
        trunkCondition: r['trunk_condition'] as String?,
        branchCondition: r['branch_condition'] as String?,
        crownCondition: r['crown_condition'] as String?,
        pests: r['pests'] as String?,
        visibleInclination: r['visible_inclination'] as String?,
        observations: r['observations'] as String?,
        photos: _list(r['photos']),
      );
}

/// Umbrales de alerta. null = desactivado (por defecto). No existen umbrales
/// universales de seguridad para árboles: debe definirlos un profesional.
class AlertSettings {
  final double? angleChangeDeg; // variación respecto a la referencia
  final double? movementMs2; // pico de aceleración lineal en una sesión
  final double? sessionDiffDeg; // diferencia entre sesiones comparables

  const AlertSettings(
      {this.angleChangeDeg, this.movementMs2, this.sessionDiffDeg});

  Map<String, double?> toJson() => {
        'angleChangeDeg': angleChangeDeg,
        'movementMs2': movementMs2,
        'sessionDiffDeg': sessionDiffDeg,
      };

  factory AlertSettings.fromJson(Map<String, dynamic> j) => AlertSettings(
        angleChangeDeg: _d(j['angleChangeDeg']),
        movementMs2: _d(j['movementMs2']),
        sessionDiffDeg: _d(j['sessionDiffDeg']),
      );
}
