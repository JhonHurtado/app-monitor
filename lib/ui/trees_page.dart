import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../analysis/alerts.dart';
import '../analysis/summary.dart';
import '../app.dart';
import '../data/models.dart';
import '../sensors/tilt.dart';
import 'common.dart';
import 'inspections.dart';
import 'monitor_page.dart';

const visualStatusOptions = [
  'Sin evaluar',
  'Buen aspecto',
  'Aspecto regular',
  'Aspecto deficiente',
];

class TreesPage extends StatefulWidget {
  const TreesPage({super.key});

  @override
  State<TreesPage> createState() => _TreesPageState();
}

class _TreesPageState extends State<TreesPage> {
  var _query = '';
  var _archived = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Árboles')),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Nuevo árbol'),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const TreeFormPage())),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Buscar por código, especie o ubicación'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SwitchListTile(
            title: const Text('Mostrar archivados'),
            value: _archived,
            onChanged: (v) => setState(() => _archived = v),
          ),
          Expanded(
            child: Loader(
              keys: [_query, _archived],
              load: () => repo.trees(archived: _archived, query: _query),
              builder: (context, trees) => trees.isEmpty
                  ? MessageView(
                      icon: Icons.park_outlined,
                      title: _query.isEmpty
                          ? (_archived ? 'No hay árboles archivados' : 'No hay árboles registrados')
                          : 'Sin resultados',
                      text: _query.isEmpty && !_archived
                          ? 'Pulsa «Nuevo árbol» para registrar el primero.'
                          : null)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      children: [
                        for (final t in trees)
                          Card(
                            child: ListTile(
                              leading: t.photos.isEmpty
                                  ? const CircleAvatar(child: Icon(Icons.park))
                                  : PhotoThumb(t.photos.first, size: 44),
                              title: Text(t.code),
                              subtitle: Text([
                                t.species ?? 'Especie no indicada',
                                if (t.location != null) t.location!,
                              ].join(' · ')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => TreeDetailPage(treeId: t.id!))),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ]),
      );
}

class TreeFormPage extends StatefulWidget {
  final Tree? tree;
  const TreeFormPage({super.key, this.tree});

  @override
  State<TreeFormPage> createState() => _TreeFormPageState();
}

class _TreeFormPageState extends State<TreeFormPage> {
  final _form = GlobalKey<FormState>();
  late final Tree? t = widget.tree;
  late final _code = TextEditingController(text: t?.code);
  late final _species = TextEditingController(text: t?.species);
  late final _location = TextEditingController(text: t?.location);
  late final _lat = TextEditingController(text: _txt(t?.latitude, 6));
  late final _lng = TextEditingController(text: _txt(t?.longitude, 6));
  late final _height = TextEditingController(text: _txt(t?.heightM, 2));
  late final _diameter = TextEditingController(text: _txt(t?.trunkDiameterCm, 1));
  late final _notes = TextEditingController(text: t?.notes);
  late String? _status = t?.visualStatus;
  late List<String> _photos = [...?t?.photos];
  var _locating = false;

  static String _txt(double? v, int d) => v == null ? '' : v.toStringAsFixed(d);
  static double? _num(String s) =>
      s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));
  static String? _empty(String s) => s.trim().isEmpty ? null : s.trim();

  String? Function(String?) _range(double min, double max, {bool exclusiveMin = false}) => (s) {
        if (s == null || s.trim().isEmpty) return null;
        final v = _num(s);
        if (v == null) return 'Número no válido';
        if (v > max || v < min || (exclusiveMin && v == min)) {
          return 'Debe estar entre ${fmt(min, 0)} y ${fmt(max, 0)}';
        }
        return null;
      };

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'El GPS está desactivado.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Permiso de ubicación denegado.';
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 30)));
      _lat.text = pos.latitude.toStringAsFixed(6);
      _lng.text = pos.longitude.toStringAsFixed(6);
      if (mounted) snack(context, 'Ubicación obtenida (precisión ±${fmt(pos.accuracy, 0)} m)');
    } catch (e) {
      if (mounted) snack(context, 'No se pudo obtener la ubicación: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final lat = _num(_lat.text), lng = _num(_lng.text);
    if ((lat == null) != (lng == null)) {
      snack(context, 'Indica latitud y longitud, o ninguna.');
      return;
    }
    try {
      final id = await repo.saveTree(Tree(
        id: t?.id,
        code: _code.text.trim(),
        species: _empty(_species.text),
        location: _empty(_location.text),
        latitude: lat,
        longitude: lng,
        heightM: _num(_height.text),
        trunkDiameterCm: _num(_diameter.text),
        visualStatus: _status,
        notes: _empty(_notes.text),
        photos: _photos,
        createdAt: t?.createdAt ?? DateTime.now(),
        archivedAt: t?.archivedAt,
      ));
      if (!mounted) return;
      if (t == null) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => TreeDetailPage(treeId: id)));
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) snack(context, 'No se pudo guardar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    const decimal = TextInputType.numberWithOptions(decimal: true, signed: true);
    return Scaffold(
      appBar: AppBar(title: Text(t == null ? 'Nuevo árbol' : 'Editar árbol')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _code,
            decoration: const InputDecoration(labelText: 'Nombre o código *'),
            validator: (s) => s == null || s.trim().isEmpty ? 'Obligatorio' : null,
          ),
          gap,
          TextFormField(controller: _species, decoration: const InputDecoration(labelText: 'Especie')),
          gap,
          TextFormField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Ubicación (descripción)')),
          gap,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _lat,
                keyboardType: decimal,
                validator: _range(-90, 90),
                decoration: const InputDecoration(labelText: 'Latitud'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _lng,
                keyboardType: decimal,
                validator: _range(-180, 180),
                decoration: const InputDecoration(labelText: 'Longitud'),
              ),
            ),
          ]),
          TextButton.icon(
            onPressed: _locating ? null : _locate,
            icon: _locating
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: const Text('Usar ubicación actual'),
          ),
          gap,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _height,
                keyboardType: decimal,
                validator: _range(0, 150, exclusiveMin: true),
                decoration: const InputDecoration(labelText: 'Altura aprox.', suffixText: 'm'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _diameter,
                keyboardType: decimal,
                validator: _range(0, 2000, exclusiveMin: true),
                decoration: const InputDecoration(labelText: 'Diámetro tronco', suffixText: 'cm'),
              ),
            ),
          ]),
          gap,
          ChoiceField(
              label: 'Estado visual (según observación)',
              options: visualStatusOptions,
              value: _status,
              onChanged: (v) => setState(() => _status = v)),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Observaciones'),
          ),
          const SectionTitle('Fotografías'),
          PhotoField(photos: _photos, onChanged: (p) => setState(() => _photos = p)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Guardar')),
        ]),
      ),
    );
  }
}

class TreeDetailPage extends StatelessWidget {
  final int treeId;
  const TreeDetailPage({super.key, required this.treeId});

  Future<(Tree?, List<Session>, List<Inspection>)> _load() async => (
        await repo.tree(treeId),
        await repo.sessions(treeId: treeId),
        await repo.inspections(treeId),
      );

  @override
  Widget build(BuildContext context) => Loader(
        load: _load,
        builder: (context, data) {
          final (tree, sessions, inspections) = data;
          if (tree == null) {
            return Scaffold(
                appBar: AppBar(),
                body: const MessageView(icon: Icons.search_off, title: 'Árbol no encontrado'));
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(tree.code),
              actions: [
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => TreeFormPage(tree: tree))),
                ),
                IconButton(
                  tooltip: tree.archived ? 'Restaurar' : 'Archivar',
                  icon: Icon(tree.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                  onPressed: () async {
                    if (!tree.archived &&
                        !await confirm(context, 'Archivar árbol',
                            'El árbol dejará de aparecer en la lista activa. Su historial se conserva y puede restaurarse.',
                            action: 'Archivar')) {
                      return;
                    }
                    await repo.setArchived(tree.id!, !tree.archived);
                  },
                ),
              ],
            ),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              if (tree.archived) const Notice('Árbol archivado.', icon: Icons.archive_outlined),
              _InfoCard(tree),
              if (tree.photos.isNotEmpty) ...[
                const SectionTitle('Fotografías'),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final p in tree.photos) PhotoThumb(p)]),
              ],
              const SizedBox(height: 12),
              if (!tree.archived)
                FilledButton.icon(
                  icon: const Icon(Icons.straighten),
                  label: const Text('Medir inclinación'),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SessionSetupPage(treeId: tree.id))),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Nueva inspección visual'),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => InspectionFormPage(treeId: tree.id!))),
              ),
              _Evolution(sessions),
              SectionTitle('Sesiones (${sessions.length})'),
              if (sessions.isEmpty)
                const Text('Sin sesiones de medición.')
              else
                for (final s in sessions) SessionTile(s, treeCode: dateLabel(s.startedAt)),
              SectionTitle('Inspecciones (${inspections.length})',
                  trailing: inspections.length < 2
                      ? null
                      : TextButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => InspectionComparePage(inspections: inspections))),
                          child: const Text('Comparar'))),
              if (inspections.isEmpty)
                const Text('Sin inspecciones visuales.')
              else
                for (final i in inspections)
                  Card(
                    child: ListTile(
                      leading: i.photos.isEmpty
                          ? const CircleAvatar(child: Icon(Icons.visibility))
                          : PhotoThumb(i.photos.first, size: 44),
                      title: Text(dateLabel(i.createdAt)),
                      subtitle: Text(inspectionSummary(i), maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => InspectionFormPage(treeId: tree.id!, inspection: i))),
                    ),
                  ),
              const SizedBox(height: 24),
            ]),
          );
        },
      );
}

class _InfoCard extends StatelessWidget {
  final Tree t;
  const _InfoCard(this.t);

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?)>[
      ('Especie', t.species),
      ('Ubicación', t.location),
      ('Coordenadas',
          t.latitude == null ? null : '${t.latitude!.toStringAsFixed(6)}, ${t.longitude!.toStringAsFixed(6)}'),
      ('Altura aprox.', t.heightM == null ? null : '${fmt(t.heightM, 1)} m'),
      ('Diámetro del tronco', t.trunkDiameterCm == null ? null : '${fmt(t.trunkDiameterCm, 1)} cm'),
      ('Estado visual', t.visualStatus),
      ('Registrado', dateLabel(t.createdAt)),
      ('Observaciones', t.notes),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          for (final (k, v) in rows)
            if (v != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 140, child: Text(k, style: Theme.of(context).textTheme.labelLarge)),
                  Expanded(child: Text(v)),
                ]),
              ),
        ]),
      ),
    );
  }
}

/// Evolución de la inclinación final entre sesiones completadas del árbol.
class _Evolution extends StatelessWidget {
  final List<Session> sessions;
  const _Evolution(this.sessions);

  @override
  Widget build(BuildContext context) {
    final done = sessions.reversed
        .where((s) => s.status == SessionStatus.completed && SessionSummary.ofSession(s)?.last != null)
        .toList();
    if (done.length < 2) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    double x(Session s) => s.startedAt.millisecondsSinceEpoch.toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Evolución entre sesiones'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SeriesChart(
            unit: '°',
            xLabel: (v) => dateLabel(DateTime.fromMillisecondsSinceEpoch(v.round())).substring(0, 5),
            series: [
              (
                label: 'Lateral final',
                color: c.primary,
                spots: [for (final s in done) FlSpot(x(s), SessionSummary.ofSession(s)!.last!.lateral)]
              ),
              (
                label: 'Frontal final',
                color: c.tertiary,
                spots: [for (final s in done) FlSpot(x(s), SessionSummary.ofSession(s)!.last!.frontal)]
              ),
            ],
          ),
        ),
      ),
      Text('Ángulos absolutos del teléfono. Solo son comparables si se usó el mismo soporte y colocación.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
