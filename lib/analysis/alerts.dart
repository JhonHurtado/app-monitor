import '../data/models.dart';
import '../sensors/tilt.dart';
import 'summary.dart';

/// Alertas descriptivas: informan el dato observado frente al umbral que
/// configuró el usuario. Nunca concluyen nada sobre la salud o el riesgo del
/// árbol. Sin umbrales configurados no se genera ninguna.
List<String> sessionAlerts(
  SessionSummary s,
  AlertSettings cfg, {
  SessionSummary? previous,
  DateTime? previousDate,
  bool sameReference = false,
}) {
  final out = <String>[];

  final angle = cfg.angleChangeDeg;
  if (angle != null) {
    final fin = s.finalDeltaRef;
    final max = s.deltaRef?.max;
    if (fin != null && fin >= angle) {
      out.add('La inclinación registrada difiere ${fmt(fin)}° de la referencia '
          '(umbral configurado: ${fmt(angle)}°).');
    } else if (max != null && max >= angle) {
      out.add('Durante la sesión la variación respecto a la referencia llegó a '
          '${fmt(max)}°, aunque al final fue ${fmt(fin)}° '
          '(umbral configurado: ${fmt(angle)}°).');
    }
  }

  final mov = cfg.movementMs2;
  final peak = s.linMagnitude?.max;
  if (mov != null && peak != null && peak >= mov) {
    out.add('Se registró un pico de aceleración lineal de ${fmt(peak, 2)} m/s² '
        '(umbral configurado: ${fmt(mov, 2)} m/s²).');
  }

  final diff = cfg.sessionDiffDeg;
  final a = s.last, b = previous?.last;
  if (diff != null && a != null && b != null) {
    final d = angleBetween(gravityDirection(a.lateral, a.frontal),
        gravityDirection(b.lateral, b.frontal));
    if (d >= diff) {
      final when = previousDate == null
          ? 'la sesión anterior'
          : 'la sesión del ${dateLabel(previousDate)}';
      out.add('La inclinación final difiere ${fmt(d)}° de $when '
          '(umbral configurado: ${fmt(diff)}°).'
          '${sameReference ? '' : ' Las sesiones usan referencias distintas: '
              'solo son comparables si el teléfono se colocó en el mismo soporte.'}');
    }
  }
  return out;
}

String dateLabel(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
