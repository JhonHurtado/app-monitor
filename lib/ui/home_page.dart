import 'package:flutter/material.dart';

import '../analysis/summary.dart';
import '../app.dart';
import '../data/models.dart';
import 'common.dart';
import 'monitor_page.dart';
import 'settings_page.dart';
import 'trees_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<(List<Tree>, List<Session>)> _load() async =>
      (await repo.trees(), await repo.sessions());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Monitor de Árboles'),
          actions: [
            IconButton(
              tooltip: 'Umbrales de alerta',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
          ],
        ),
        body: Loader(
          load: _load,
          builder: (context, data) {
            final (trees, sessions) = data;
            final codes = {for (final t in trees) t.id: t.code};
            final review = sessions
                .where((s) =>
                    s.incomplete ||
                    SessionSummary.ofSession(s)?.quality != Quality.buena)
                .length;
            return ListView(padding: const EdgeInsets.all(16), children: [
              StatRow([
                StatTile('Árboles activos', '${trees.length}'),
                StatTile('Sesiones', '${sessions.length}'),
                StatTile('Por revisar', '$review'),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar medición'),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SessionSetupPage())),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Registrar árbol'),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const TreeFormPage())),
              ),
              SectionTitle('Últimas mediciones',
                  trailing: sessions.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () => HomeShell.goTo(context, 3),
                          child: const Text('Ver historial'))),
              if (sessions.isEmpty)
                const MessageView(
                    icon: Icons.sensors_off_outlined,
                    title: 'Aún no hay mediciones',
                    text: 'Registra un árbol e inicia una sesión de medición.')
              else
                for (final s in sessions.take(5))
                  SessionTile(s, treeCode: codes[s.treeId] ?? 'Árbol archivado'),
              const SizedBox(height: 12),
              const Notice(
                  'Las lecturas del teléfono describen la orientación del dispositivo. '
                  'No determinan el estado de salud ni el riesgo de un árbol: para eso '
                  'se requiere un profesional e instrumentación adecuada.'),
            ]);
          },
        ),
      );
}
