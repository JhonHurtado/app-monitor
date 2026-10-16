import 'dart:math' as math;

import 'package:arbol_monitor/sensors/tilt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const g = standardGravity;

  test('conversión de unidades grados/radianes', () {
    expect(toDegrees(math.pi), closeTo(180, 1e-12));
    expect(toRadians(90), closeTo(math.pi / 2, 1e-12));
    expect(toDegrees(toRadians(12.34)), closeTo(12.34, 1e-12));
  });

  test('teléfono vertical = 0° en ambos ejes', () {
    final t = Tilt.fromGravity(const Vec3(0, g, 0));
    expect(t.lateral, closeTo(0, 1e-9));
    expect(t.frontal, closeTo(0, 1e-9));
    expect(t.fromVertical, closeTo(0, 1e-9));
    expect(t.offAxis, isFalse);
  });

  test('inclinación lateral de 10° (parte superior a la derecha)', () {
    final a = toRadians(10);
    final t = Tilt.fromGravity(Vec3(-g * math.sin(a), g * math.cos(a), 0));
    expect(t.lateral, closeTo(10, 1e-9));
    expect(t.frontal, closeTo(0, 1e-9));
    expect(t.fromVertical, closeTo(10, 1e-9));
  });

  test('inclinación frontal de 5° (pantalla hacia arriba)', () {
    final a = toRadians(5);
    final t = Tilt.fromGravity(Vec3(0, g * math.cos(a), g * math.sin(a)));
    expect(t.frontal, closeTo(5, 1e-9));
    expect(t.lateral, closeTo(0, 1e-9));
  });

  test('teléfono plano queda fuera de eje', () {
    expect(Tilt.fromGravity(const Vec3(0, 0, g)).offAxis, isTrue);
  });

  test('gravityDirection es la inversa de Tilt.fromGravity', () {
    for (final (l, f) in [(0.0, 0.0), (3.2, -1.5), (-25.0, 12.0), (80.0, 5.0)]) {
      final t = Tilt.fromGravity(gravityDirection(l, f) * g);
      expect(t.lateral, closeTo(l, 1e-9));
      expect(t.frontal, closeTo(f, 1e-9));
    }
  });

  test('angleBetween es preciso con ángulos pequeños', () {
    final a = gravityDirection(0, 0), b = gravityDirection(0.01, 0);
    expect(angleBetween(a, b), closeTo(0.01, 1e-9));
    expect(angleBetween(a, a), 0);
    expect(angleBetween(const Vec3(1, 0, 0), const Vec3(0, 1, 0)), closeTo(90, 1e-9));
  });

  group('filtro de gravedad', () {
    test('converge al valor constante y atenúa el ruido', () {
      final f = GravityFilter(tauSeconds: 0.5);
      final rnd = math.Random(1);
      var t = DateTime(2026);
      Vec3? out;
      for (var i = 0; i < 500; i++) {
        t = t.add(const Duration(milliseconds: 20));
        final noise = Vec3(rnd.nextDouble() - .5, rnd.nextDouble() - .5, rnd.nextDouble() - .5);
        out = f.add(const Vec3(0, g, 0) + noise, t);
      }
      expect(Tilt.fromGravity(out!).fromVertical, lessThan(1.0));
    });

    test('ignora lecturas inválidas', () {
      final f = GravityFilter();
      f.add(const Vec3(0, g, 0), DateTime(2026));
      expect(f.add(const Vec3(double.nan, 0, 0), DateTime(2026, 1, 1, 0, 0, 1)), isNull);
      expect(f.value!.y, g);
    });

    test('la primera lectura inicializa el filtro', () {
      final f = GravityFilter();
      expect(f.add(const Vec3(1, 2, 3), DateTime(2026))!.z, 3);
    });
  });

  group('calibración', () {
    test('promedia lecturas y mide la estabilidad', () {
      final c = Calibration.fromReadings([
        for (var i = 0; i < 50; i++) gravityDirection(i.isEven ? 0.1 : -0.1, 2) * g,
      ], DateTime(2026))!;
      expect(c.tilt.lateral, closeTo(0, 1e-6));
      expect(c.tilt.frontal, closeTo(2, 1e-4)); // promediar vectores acorta la componente en el plano
      expect(c.stdDeg, closeTo(0.1, 1e-3));
      expect(c.isStable, isTrue);
    });

    test('detecta movimiento durante la calibración', () {
      final c = Calibration.fromReadings([
        for (var i = 0; i < 50; i++) gravityDirection(i.isEven ? 3 : -3, 0) * g,
      ], DateTime(2026))!;
      expect(c.isStable, isFalse);
    });

    test('requiere lecturas suficientes y válidas', () {
      expect(Calibration.fromReadings([const Vec3(0, g, 0)], DateTime(2026)), isNull);
      expect(
          Calibration.fromReadings(
              List.filled(10, const Vec3(double.nan, 0, 0)), DateTime(2026)),
          isNull);
    });

    test('ida y vuelta JSON conserva la referencia', () {
      final c = Calibration(gravityDirection(4, -1) * g, 80, 0.2, DateTime(2026, 5, 1))
          .reusedFrom(7);
      final back = Calibration.fromJson(c.toJson());
      expect(back.tilt.lateral, closeTo(4, 1e-9));
      expect(back.sourceSessionId, 7);
      expect(back.at, DateTime(2026, 5, 1));
    });
  });

  test('fmt usa coma decimal', () {
    expect(fmt(2.54), '2,5');
    expect(fmt(null), '—');
    expect(fmt(double.nan), '—');
    expect(fmt(-0.0001, 2), '0,00');
    expect(fmt(-1.25, 2), '-1,25');
  });
}
