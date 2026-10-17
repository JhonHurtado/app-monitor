import 'package:arbol_monitor/analysis/alerts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aviso en vivo se activa en el umbral de variación de inclinación', () {
    expect(hasLiveTiltAlert(liveTiltAlertThresholdDeg - 0.01), isFalse);
    expect(hasLiveTiltAlert(liveTiltAlertThresholdDeg), isTrue);
    expect(hasLiveTiltAlert(liveTiltAlertThresholdDeg + 0.01), isTrue);
  });
}
