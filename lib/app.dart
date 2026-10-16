import 'package:flutter/material.dart';

import 'data/repo.dart';
import 'sensors/device.dart';
import 'ui/history_page.dart';
import 'ui/home_page.dart';
import 'ui/monitor_page.dart';
import 'ui/trees_page.dart';

// ponytail: servicios globales en lugar de un contenedor de inyección; las
// pruebas los sustituyen antes de construir la app.
late Repo repo;
SensorSources sensors = SensorSources.device();

const _forest = Color(0xFF2F6B3B);

ThemeData _theme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
      seedColor: _forest, brightness: b, tertiary: const Color(0xFF7A5A3A));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 52))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52))),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

class ArbolApp extends StatelessWidget {
  const ArbolApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Monitor de Árboles',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Permite que otras pantallas cambien de pestaña (accesos rápidos).
  static void goTo(BuildContext context, int tab) =>
      context.findAncestorStateOfType<_HomeShellState>()?._go(tab);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _tab = 0;
  void _go(int t) => setState(() => _tab = t);

  @override
  Widget build(BuildContext context) => Scaffold(
        // Solo se construye la pestaña visible: la de Monitoreo no mantiene
        // sensores activos mientras no se ve.
        body: switch (_tab) {
          0 => const HomePage(),
          1 => const TreesPage(),
          2 => const MonitorPage(),
          _ => const HistoryPage(),
        },
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _go,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
            NavigationDestination(icon: Icon(Icons.park_outlined), selectedIcon: Icon(Icons.park), label: 'Árboles'),
            NavigationDestination(icon: Icon(Icons.sensors_outlined), selectedIcon: Icon(Icons.sensors), label: 'Monitoreo'),
            NavigationDestination(icon: Icon(Icons.show_chart_outlined), selectedIcon: Icon(Icons.show_chart), label: 'Historial'),
          ],
        ),
      );
}
