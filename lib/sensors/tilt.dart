import 'dart:math' as math;

/// Vector 3D en el sistema de coordenadas del dispositivo Android:
///   x → hacia la derecha de la pantalla
///   y → hacia la parte superior de la pantalla
///   z → saliendo de la pantalla, hacia el usuario
/// El acelerómetro mide aceleración propia: en reposo y vertical lee y ≈ +9,81 m/s².
class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);

  static const zero = Vec3(0, 0, 0);

  double get norm => math.sqrt(x * x + y * y + z * z);
  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  Map<String, double> toJson() => {'x': x, 'y': y, 'z': z};
  factory Vec3.fromJson(Map<String, dynamic> j) =>
      Vec3((j['x'] as num).toDouble(), (j['y'] as num).toDouble(),
          (j['z'] as num).toDouble());

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

const standardGravity = 9.80665; // m/s²

double toDegrees(double rad) => rad * 180 / math.pi;
double toRadians(double deg) => deg * math.pi / 180;

/// Inclinación del teléfono (en grados) para la colocación de referencia:
/// teléfono en vertical (retrato), con la parte trasera apoyada en el tronco
/// o en un soporte fijo y la parte superior hacia arriba.
///
/// * [lateral]: giro en el plano de la pantalla. Positivo = la parte superior
///   del teléfono se inclina hacia la derecha (vista desde la pantalla).
/// * [frontal]: giro fuera del plano de la pantalla. Positivo = la pantalla
///   mira hacia arriba (la parte superior se aleja del observador).
/// * [fromVertical]: ángulo total entre el eje y del teléfono y la vertical.
///
/// Es la inclinación del TELÉFONO, no la del árbol.
class Tilt {
  final double lateral, frontal, fromVertical;
  const Tilt(this.lateral, this.frontal, this.fromVertical);

  /// [g] es el vector de gravedad estimado (aceleración propia filtrada).
  factory Tilt.fromGravity(Vec3 g) {
    final lateral = toDegrees(math.atan2(-g.x, g.y));
    final frontal =
        toDegrees(math.atan2(g.z, math.sqrt(g.x * g.x + g.y * g.y)));
    final fromVertical = angleBetween(g, const Vec3(0, 1, 0));
    return Tilt(lateral, frontal, fromVertical);
  }

  /// true si el teléfono está lejos de la posición vertical de referencia
  /// (más de 60°): los ejes lateral/frontal dejan de ser interpretables.
  bool get offAxis => fromVertical > 60;
}

/// Inversa de [Tilt.fromGravity]: vector unitario de gravedad a partir de los
/// ángulos lateral y frontal (grados).
Vec3 gravityDirection(double lateralDeg, double frontalDeg) {
  final l = toRadians(lateralDeg), f = toRadians(frontalDeg);
  return Vec3(-math.cos(f) * math.sin(l), math.cos(f) * math.cos(l), math.sin(f));
}

/// Ángulo (grados) entre dos vectores. atan2(|a×b|, a·b) es preciso también
/// para ángulos pequeños, a diferencia de acos.
double angleBetween(Vec3 a, Vec3 b) =>
    toDegrees(math.atan2(a.cross(b).norm, a.dot(b)));

/// Filtro paso bajo exponencial de primer orden para separar la gravedad
/// (componente lenta) de la aceleración del acelerómetro.
/// alpha = dt / (tau + dt). tau = 0,5 s atenúa el temblor de la mano y las
/// vibraciones rápidas pero sigue cambios de inclinación en ~1-2 s.
class GravityFilter {
  final double tauSeconds;
  Vec3? _g;
  DateTime? _last;
  GravityFilter({this.tauSeconds = 0.5});

  Vec3? get value => _g;

  /// Devuelve la nueva estimación, o null si la lectura es inválida.
  Vec3? add(Vec3 a, DateTime t) {
    if (!a.isFinite) return null;
    final g = _g;
    final last = _last;
    _last = t;
    if (g == null || last == null) return _g = a;
    final dt = (t.difference(last).inMicroseconds / 1e6).clamp(0.0, 1.0);
    final alpha = dt / (tauSeconds + dt);
    return _g = g + (a - g) * alpha;
  }

  void reset() {
    _g = null;
    _last = null;
  }
}

/// Referencia angular: promedio del acelerómetro durante la calibración.
/// Promediar N lecturas reduce el ruido blanco en un factor √N.
class Calibration {
  final Vec3 gravity;
  final int samples;

  /// Desviación típica (°) del ángulo de cada lectura respecto al promedio:
  /// indica si el teléfono estuvo quieto durante la calibración.
  final double stdDeg;
  final DateTime at;

  /// Sesión de la que se reutilizó la referencia, si aplica.
  final int? sourceSessionId;

  const Calibration(this.gravity, this.samples, this.stdDeg, this.at,
      {this.sourceSessionId});

  Tilt get tilt => Tilt.fromGravity(gravity);

  /// Estabilidad aceptable para fijar una referencia (teléfono apoyado, sin
  /// sostenerlo con la mano). Es un criterio de calidad de medición, no de
  /// seguridad del árbol.
  bool get isStable => stdDeg <= 0.5;

  static Calibration? fromReadings(List<Vec3> readings, DateTime at) {
    final valid = readings.where((v) => v.isFinite && v.norm > 0).toList();
    if (valid.length < 5) return null;
    var sum = Vec3.zero;
    for (final v in valid) {
      sum = sum + v;
    }
    final mean = sum * (1 / valid.length);
    var sq = 0.0;
    for (final v in valid) {
      final d = angleBetween(v, mean);
      sq += d * d;
    }
    return Calibration(mean, valid.length, math.sqrt(sq / valid.length), at);
  }

  Calibration reusedFrom(int sessionId) =>
      Calibration(gravity, samples, stdDeg, at, sourceSessionId: sessionId);

  Map<String, dynamic> toJson() => {
        'gravity': gravity.toJson(),
        'samples': samples,
        'stdDeg': stdDeg,
        'at': at.millisecondsSinceEpoch,
        'lateralDeg': tilt.lateral,
        'frontalDeg': tilt.frontal,
        'sourceSessionId': sourceSessionId,
        'method': 'promedio acelerómetro, colocación vertical retrato',
      };

  factory Calibration.fromJson(Map<String, dynamic> j) => Calibration(
        Vec3.fromJson(j['gravity'] as Map<String, dynamic>),
        j['samples'] as int,
        (j['stdDeg'] as num).toDouble(),
        DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        sourceSessionId: j['sourceSessionId'] as int?,
      );
}

/// Formato numérico con coma decimal para la interfaz.
String fmt(double? v, [int digits = 1]) {
  if (v == null || !v.isFinite) return '—';
  var s = v.toStringAsFixed(digits);
  if (double.parse(s) == 0) s = s.replaceFirst('-', ''); // evita "-0,00"
  return s.replaceAll('.', ',');
}
