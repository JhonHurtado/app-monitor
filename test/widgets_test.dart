import 'package:arbol_monitor/app.dart';
import 'package:arbol_monitor/data/models.dart';
import 'package:arbol_monitor/ui/history_page.dart';
import 'package:arbol_monitor/ui/monitor_page.dart';
import 'package:arbol_monitor/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late FakeSensors fake;
  var clock = DateTime(2026, 6, 1);

  setUp(() async {
    repo = await memoryRepo();
    fake = FakeSensors();
    sensors = fake.sources;
  });
  tearDown(() => repo.db.close());

  // Pantalla de teléfono alta para que los ListView construyan todos los botones.
  Future<void> tall(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tall(tester);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  /// Emite lecturas del acelerómetro mientras avanza el reloj de la prueba.
  Future<void> feed(WidgetTester tester, Duration total, {double lateral = 0}) async {
    // Marca de tiempo sintética: el reloj de la prueba no avanza DateTime.now().
    const step = Duration(milliseconds: 50);
    for (var t = Duration.zero; t < total; t += step) {
      clock = clock.add(step);
      fake.lin.add(leaning(0, clock));
      fake.acc.add(leaning(lateral, clock));
      await tester.pump(step);
    }
  }

  testWidgets('navegación inferior con estados vacíos', (tester) async {
    await tester.pumpWidget(const ArbolApp());
    await tester.pumpAndSettle();
    expect(find.text('Aún no hay mediciones'), findsOneWidget);

    await tester.tap(find.text('Árboles'));
    await tester.pumpAndSettle();
    expect(find.text('No hay árboles registrados'), findsOneWidget);

    await tester.tap(find.text('Monitoreo'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva sesión de medición'), findsOneWidget);

    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();
    expect(find.text('No hay sesiones con estos filtros'), findsOneWidget);
  });

  testWidgets('registrar un árbol: validación y guardado', (tester) async {
    await tall(tester);
    await tester.pumpWidget(const ArbolApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Árboles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo árbol'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Obligatorio'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre o código *'), 'Ceiba-07');
    await tester.enterText(find.widgetWithText(TextFormField, 'Especie'), 'Ceiba pentandra');
    await tester.enterText(find.widgetWithText(TextFormField, 'Latitud'), '95');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Debe estar entre -90 y 90'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Latitud'), '4,6');
    await tester.enterText(find.widgetWithText(TextFormField, 'Longitud'), '-74,08');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    // Ficha del árbol
    expect(find.text('Ceiba-07'), findsOneWidget);
    expect(find.text('Medir inclinación'), findsOneWidget);
    final saved = (await repo.trees()).single;
    expect(saved.latitude, 4.6);
    expect(saved.longitude, -74.08);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Ceiba-07'), findsOneWidget);
    expect(find.textContaining('Ceiba pentandra'), findsOneWidget);
  });

  testWidgets('sensores no disponibles se indican y bloquean la medición', (tester) async {
    fake.present = {2};
    final id = await addTree(repo);
    await pumpPage(tester, const MonitorPage());
    expect(find.text('Acelerómetro · No disponible'), findsOneWidget);
    expect(find.text('Giroscopio · No disponible'), findsOneWidget);
    expect(find.textContaining('Magnetómetro'), findsOneWidget);
    expect(find.text('Magnetómetro · No disponible'), findsNothing);

    await pumpPage(tester, SessionSetupPage(treeId: id));
    expect(find.textContaining('El acelerómetro no está disponible'), findsOneWidget);
    final start = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Iniciar sesión'), matching: find.bySubtype<ButtonStyleButton>()));
    expect(start.onPressed, isNull);
  });

  testWidgets('flujo completo: calibrar, medir, pausar, reanudar y finalizar', (tester) async {
    final id = await addTree(repo, 'Roble-01');
    await pumpPage(tester, SessionSetupPage(treeId: id));
    expect(find.text('Calibra la referencia.'), findsOneWidget);

    await tester.tap(find.text('Calibrar'));
    await tester.pump();
    await feed(tester, const Duration(milliseconds: 2100));
    await tester.pumpAndSettle();
    expect(find.textContaining('Referencia: lateral 0,00°'), findsOneWidget);

    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Grabando'), findsOneWidget);
    expect(fake.screenOn, isTrue);

    await feed(tester, const Duration(seconds: 3), lateral: 1);
    expect(find.text('Δ lateral'), findsWidgets);
    final session = (await repo.sessions()).single;
    expect(session.status, SessionStatus.running);
    expect(await repo.sampleCount(session.id!), greaterThan(0), reason: 'lotes escritos cada segundo');

    await tester.tap(find.text('Pausar'));
    await tester.pump();
    await tester.pump();
    expect(find.text('En pausa'), findsOneWidget);
    expect((await repo.session(session.id!))!.status, SessionStatus.paused);

    await tester.tap(find.text('Reanudar'));
    await tester.pump();
    await feed(tester, const Duration(seconds: 1), lateral: 1);

    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Prueba de campo');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Finalizar')));
    await tester.pumpAndSettle();

    final done = (await repo.session(session.id!))!;
    expect(done.status, SessionStatus.completed);
    expect(done.notes, 'Prueba de campo');
    expect(done.summary!['finalDeltaLateralDeg'], closeTo(1, 0.05));
    expect(find.text('Datos de la sesión'), findsOneWidget);
    expect(fake.screenOn, isFalse);
    expect(fake.acc.hasListener, isFalse, reason: 'sensores liberados al terminar');
  });

  testWidgets('eliminar una sesión requiere confirmación', (tester) async {
    final tree = await addTree(repo);
    final id = await repo.createSession(Session(
        treeId: tree, startedAt: DateTime(2026, 5, 1), samplingHz: 20, calibration: vertical().toJson()));
    await repo.closeSession(id, SessionStatus.completed);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (c) => TextButton(
                onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => SessionDetailPage(sessionId: id))),
                child: const Text('abrir')))));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await repo.session(id), isNotNull);

    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(await repo.session(id), isNull);
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('umbrales de alerta vacíos por defecto y validados', (tester) async {
    await pumpPage(tester, const SettingsPage());
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    for (final e in tester.widgetList<TextFormField>(fields)) {
      expect(e.controller!.text, isEmpty);
    }
    await tester.enterText(fields.first, '-2');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('mayor que 0'), findsOneWidget);
    await tester.enterText(fields.first, '2,5');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect((await repo.alertSettings()).angleChangeDeg, 2.5);
  });
}
