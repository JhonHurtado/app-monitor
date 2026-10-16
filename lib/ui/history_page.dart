import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../analysis/alerts.dart';
import '../analysis/summary.dart';
import '../app.dart';
import '../data/export.dart';
import '../data/models.dart';
import '../sensors/tilt.dart';
import 'common.dart';
import 'live_session_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  int? _treeId;
  DateTimeRange? _range;
  var _onlyIncomplete = false;
  var _exporting = false;

  Future<(List<Tree>, List<Session>)> _load() async => (
        [...await repo.trees(), ...await repo.trees(archived: true)],
        await repo.sessions(
          treeId: _treeId,
          from: _range?.start,
          to: _range?.end.add(const Duration(days: 1)),
          onlyIncomplete: _onlyIncomplete,
        ),
      );

  Future<void> _export(List<Session> sessions) async {
    setState(() => _exporting = true);
    try {
      await exportAndShare(repo, sessions);
    } catch (e) {
      if (mounted) snack(context, 'No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Loader(
        keys: [_treeId, _range, _onlyIncomplete],
        load: _load,
        builder: (context, data) {
          final (trees, sessions) = data;
          final codes = {for (final t in trees) t.id: t.code};
          final c = Theme.of(context).colorScheme;
          final done = sessions.reversed
              .where((s) => s.status == SessionStatus.completed && SessionSummary.ofSession(s)?.last != null)
              .toList();
          double x(Session s) => s.startedAt.millisecondsSinceEpoch.toDouble();
          String day(double v) => dateLabel(DateTime.fromMillisecondsSinceEpoch(v.round())).substring(0, 5);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Historial'),
              actions: [
                IconButton(
                  tooltip: 'Comparar sesiones',
                  icon: const Icon(Icons.compare_arrows),
                  onPressed: sessions.length < 2
                      ? null
                      : () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => ComparePage(sessions: sessions, treeCodes: codes))),
                ),
                IconButton(
                  tooltip: 'Exportar CSV y JSON',
                  icon: _exporting
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.ios_share),
                  onPressed: sessions.isEmpty || _exporting ? null : () => _export(sessions),
                ),
              ],
            ),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              DropdownButtonFormField<int?>(
                initialValue: _treeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Árbol'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos los árboles')),
                  for (final t in trees)
                    DropdownMenuItem(value: t.id, child: Text(t.archived ? '${t.code} (archivado)' : t.code)),
                ],
                onChanged: (v) => setState(() => _treeId = v),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(_range == null
                      ? 'Todas las fechas'
                      : '${dateLabel(_range!.start).substring(0, 10)} – ${dateLabel(_range!.end).substring(0, 10)}'),
                  onPressed: () async {
                    final r = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      initialDateRange: _range,
                    );
                    if (r != null) setState(() => _range = r);
                  },
                ),
                if (_range != null)
                  IconButton(
                      tooltip: 'Quitar filtro de fechas',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _range = null)),
                FilterChip(
                  label: const Text('Solo incompletas'),
                  selected: _onlyIncomplete,
                  onSelected: (v) => setState(() => _onlyIncomplete = v),
                ),
              ]),
              if (done.length >= 2) ...[
                const SectionTitle('Evolución de la inclinación'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SeriesChart(unit: '°', xLabel: day, series: [
                      (
                        label: 'Δ final vs ref.',
                        color: c.primary,
                        spots: [for (final s in done) FlSpot(x(s), SessionSummary.ofSession(s)!.finalDeltaRef!)],
                      ),
                      (
                        label: 'Δ máx. vs ref.',
                        color: c.tertiary,
                        spots: [
                          for (final s in done)
                            if (SessionSummary.ofSession(s)!.deltaRef != null)
                              FlSpot(x(s), SessionSummary.ofSession(s)!.deltaRef!.max)
                        ],
                      ),
                    ]),
                  ),
                ),
                if (done.any((s) => SessionSummary.ofSession(s)!.linMagnitude != null)) ...[
                  const SectionTitle('Evolución del movimiento'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SeriesChart(unit: 'm/s²', xLabel: day, series: [
                        (
                          label: 'Pico de aceleración lineal',
                          color: c.secondary,
                          spots: [
                            for (final s in done)
                              if (SessionSummary.ofSession(s)!.linMagnitude != null)
                                FlSpot(x(s), SessionSummary.ofSession(s)!.linMagnitude!.max)
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
                if (_treeId == null)
                  Text('Incluye sesiones de varios árboles. Filtra por árbol para ver su evolución.',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
              SectionTitle('Sesiones (${sessions.length})'),
              if (sessions.isEmpty)
                const MessageView(icon: Icons.history, title: 'No hay sesiones con estos filtros')
              else
                for (final s in sessions) SessionTile(s, treeCode: codes[s.treeId]),
            ]),
          );
        },
      );
}

class SessionDetailPage extends StatelessWidget {
  final int sessionId;
  const SessionDetailPage({super.key, required this.sessionId});

  Future<_Detail?> _load() async {
    final s = await repo.session(sessionId);
    if (s == null) return null;
    final siblings = await repo.sessions(treeId: s.treeId);
    return _Detail(
      s,
      (await repo.tree(s.treeId))!,
      await repo.samples(sessionId),
      siblings
          .where((o) => o.status == SessionStatus.completed && o.startedAt.isBefore(s.startedAt))
          .firstOrNull,
      await repo.alertSettings(),
    );
  }

  @override
  Widget build(BuildContext context) => Loader(
        load: _load,
        builder: (context, d) => d == null
            ? Scaffold(appBar: AppBar(), body: const MessageView(icon: Icons.search_off, title: 'Sesión no encontrada'))
            : _SessionDetailView(d),
      );
}

class _Detail {
  final Session s;
  final Tree tree;
  final List<Sample> samples;
  final Session? previous;
  final AlertSettings cfg;
  _Detail(this.s, this.tree, this.samples, this.previous, this.cfg);
}

class _SessionDetailView extends StatelessWidget {
  final _Detail d;
  const _SessionDetailView(this.d);

  Session get s => d.s;

  Future<void> _resume(BuildContext context) async {
    final hz = s.samplingHz;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveSessionPage(
          sessionId: s.id!,
          treeCode: d.tree.code,
          reference: Calibration.fromJson(s.calibration),
          hz: hz,
          useLinear: s.sensors.contains('linear_acceleration'),
          useGyro: s.sensors.contains('gyroscope'),
          // ponytail: tiempo activo previo estimado por nº de muestras / frecuencia
          previouslyActive: Duration(milliseconds: (d.samples.length / hz * 1000).round()),
        ),
      ),
    );
  }

  Future<void> _finishPaused() async => repo.closeSession(s.id!, SessionStatus.completed,
      activeSeconds: d.samples.length / s.samplingHz);

  Future<void> _delete(BuildContext context) async {
    if (!await confirm(context, 'Eliminar sesión',
        'Se eliminarán la sesión y sus ${d.samples.length} muestras. Esta acción no se puede deshacer.')) {
      return;
    }
    await repo.deleteSession(s.id!);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _export(BuildContext context) async {
    try {
      await exportAndShare(repo, [s]);
    } catch (e) {
      if (context.mounted) snack(context, 'No se pudo exportar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final sum = SessionSummary.ofSession(s);
    final ref = Calibration.fromJson(s.calibration);
    final prev = d.previous == null ? null : SessionSummary.ofSession(d.previous!);
    final alerts = sum == null
        ? const <String>[]
        : sessionAlerts(sum, d.cfg,
            previous: prev,
            previousDate: d.previous?.startedAt,
            sameReference: d.previous != null && d.previous!.calibration['at'] == s.calibration['at']);
    final paused = s.status == SessionStatus.paused;

    return Scaffold(
      appBar: AppBar(
        title: Text('${d.tree.code} · ${dateLabel(s.startedAt).substring(0, 10)}'),
        actions: [
          IconButton(tooltip: 'Exportar', icon: const Icon(Icons.ios_share), onPressed: () => _export(context)),
          IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [QualityChip(s), const Spacer(), Text('Sesión #${s.id}', style: t.bodySmall)]),
        if (paused) ...[
          const Notice('Sesión en pausa. Puedes reanudarla con el teléfono en el mismo soporte o finalizarla.'),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => _resume(context), icon: const Icon(Icons.play_arrow), label: const Text('Reanudar'))),
            const SizedBox(width: 12),
            Expanded(
                child: FilledButton.icon(
                    onPressed: _finishPaused, icon: const Icon(Icons.stop), label: const Text('Finalizar'))),
          ]),
        ],
        for (final a in alerts) Notice(a, icon: Icons.notifications_active_outlined, warning: true),
        if (sum != null && sum.issues.isNotEmpty)
          Notice('Calidad de la medición:\n• ${sum.issues.join('\n• ')}', icon: Icons.rule),
        const SectionTitle('Datos de la sesión'),
        _KeyValues({
          'Inicio': dateLabel(s.startedAt),
          'Fin': s.endedAt == null ? '—' : dateLabel(s.endedAt!),
          'Duración': durationLabel(s.duration),
          'Tiempo activo': sum == null ? '—' : durationLabel(Duration(seconds: sum.activeSeconds.round())),
          'Frecuencia': '${fmt(s.samplingHz, 0)} Hz',
          'Muestras': sum == null ? '${d.samples.length}' : '${sum.sampleCount} de ~${sum.expectedSamples} esperadas',
          'Sensores': s.sensors.map(_sensorLabel).join(', '),
          'Colocación': s.conditions['placement'] as String? ?? '—',
          'Viento': s.conditions['wind'] as String? ?? '—',
          'Referencia': 'lateral ${fmt(ref.tilt.lateral, 2)}°, frontal ${fmt(ref.tilt.frontal, 2)}° '
              '(σ ${fmt(ref.stdDeg, 2)}°, ${ref.samples} lecturas'
              '${ref.sourceSessionId == null ? '' : ', reutilizada de la sesión #${ref.sourceSessionId}'})',
          if (sum?.movementEvents != null) 'Eventos de movimiento': '${sum!.movementEvents}',
        }),
        if (sum != null) ...[
          const SectionTitle('Inicial y final'),
          StatRow([
            StatTile('Lateral inicial → final',
                '${fmt(sum.initial?.lateral, 2)} → ${fmt(sum.last?.lateral, 2)}', unit: '°'),
            StatTile('Frontal inicial → final',
                '${fmt(sum.initial?.frontal, 2)} → ${fmt(sum.last?.frontal, 2)}', unit: '°'),
          ]),
          StatRow([
            StatTile('Δ lateral final', fmt(sum.finalDeltaLateral, 2), unit: '°'),
            StatTile('Δ frontal final', fmt(sum.finalDeltaFrontal, 2), unit: '°'),
            StatTile('Δ total final', fmt(sum.finalDeltaRef, 2), unit: '°'),
          ]),
          const SectionTitle('Estadísticas'),
          _StatsTable(sum),
        ],
        if (d.samples.isNotEmpty) ...[
          const SectionTitle('Variación respecto a la referencia'),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: _SamplesChart(d.samples, ref, c))),
        ],
        const SectionTitle('Notas'),
        _NotesField(s),
        const SizedBox(height: 24),
      ]),
    );
  }

  static String _sensorLabel(String s) => switch (s) {
        'accelerometer' => 'acelerómetro',
        'linear_acceleration' => 'aceleración lineal',
        'gyroscope' => 'giroscopio',
        _ => s,
      };
}

class _KeyValues extends StatelessWidget {
  final Map<String, String> values;
  const _KeyValues(this.values);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            for (final e in values.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 120, child: Text(e.key, style: Theme.of(context).textTheme.labelLarge)),
                  Expanded(child: Text(e.value)),
                ]),
              ),
          ]),
        ),
      );
}

class _StatsTable extends StatelessWidget {
  final SessionSummary sum;
  const _StatsTable(this.sum);

  @override
  Widget build(BuildContext context) {
    final rows = <(String, Stats?, int)>[
      ('Lateral (°)', sum.lateral, 2),
      ('Frontal (°)', sum.frontal, 2),
      ('Δ ref. (°)', sum.deltaRef, 2),
      ('|a| (m/s²)', sum.accMagnitude, 3),
      ('|a lineal| (m/s²)', sum.linMagnitude, 3),
      ('|ω| (rad/s)', sum.gyroMagnitude, 4),
    ];
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('')),
            DataColumn(label: Text('Mín.'), numeric: true),
            DataColumn(label: Text('Máx.'), numeric: true),
            DataColumn(label: Text('Media'), numeric: true),
            DataColumn(label: Text('σ'), numeric: true),
          ],
          rows: [
            for (final (label, st, dg) in rows)
              DataRow(cells: [
                DataCell(Text(label)),
                for (final v in [st?.min, st?.max, st?.mean, st?.std])
                  DataCell(Text(st == null ? 'N/D' : fmt(v, dg))),
              ]),
          ],
        ),
      ),
    );
  }
}

class _SamplesChart extends StatelessWidget {
  final List<Sample> samples;
  final Calibration ref;
  final ColorScheme c;
  const _SamplesChart(this.samples, this.ref, this.c);

  @override
  Widget build(BuildContext context) {
    // Reducir a ~400 puntos para dibujar con fluidez sesiones largas.
    final step = math.max(1, (samples.length / 400).ceil());
    final t0 = samples.first.t;
    final pts = [for (var i = 0; i < samples.length; i += step) samples[i]];
    double x(Sample s) => s.t.difference(t0).inMilliseconds / 1000;
    final r = ref.tilt;
    final hasLin = samples.any((s) => s.linX != null);
    return Column(children: [
      SeriesChart(unit: '°', xLabel: (v) => '${v.round()} s', series: [
        (label: 'Δ lateral', color: c.primary, spots: [for (final s in pts) FlSpot(x(s), s.inclLateral - r.lateral)]),
        (label: 'Δ frontal', color: c.tertiary, spots: [for (final s in pts) FlSpot(x(s), s.inclFrontal - r.frontal)]),
      ]),
      if (hasLin) ...[
        const SizedBox(height: 16),
        SeriesChart(unit: 'm/s²', height: 140, xLabel: (v) => '${v.round()} s', series: [
          (
            label: 'Aceleración lineal',
            color: c.secondary,
            spots: [
              for (final s in pts)
                if (s.linX != null) FlSpot(x(s), Vec3(s.linX!, s.linY!, s.linZ!).norm)
            ]
          ),
        ]),
      ],
    ]);
  }
}

class _NotesField extends StatefulWidget {
  final Session s;
  const _NotesField(this.s);

  @override
  State<_NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<_NotesField> {
  late final _c = TextEditingController(text: widget.s.notes);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        TextField(controller: _c, maxLines: 4, decoration: const InputDecoration(hintText: 'Añade notas a esta sesión')),
        TextButton(
          onPressed: () async {
            await repo.setSessionNotes(widget.s.id!, _c.text.trim());
            if (context.mounted) snack(context, 'Notas guardadas');
          },
          child: const Text('Guardar notas'),
        ),
      ]);
}

/// Comparación entre dos sesiones.
class ComparePage extends StatefulWidget {
  final List<Session> sessions; // más reciente primero
  final Map<int?, String> treeCodes;
  const ComparePage({super.key, required this.sessions, required this.treeCodes});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  late Session _a = widget.sessions[1], _b = widget.sessions[0];

  Widget _picker(Session value, ValueChanged<Session> onChanged) => DropdownButton<Session>(
        value: value,
        isExpanded: true,
        items: [
          for (final s in widget.sessions)
            DropdownMenuItem(
                value: s,
                child: Text('${widget.treeCodes[s.treeId] ?? '#${s.treeId}'} · ${dateLabel(s.startedAt)}',
                    overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => onChanged(v!)),
      );

  @override
  Widget build(BuildContext context) {
    final sa = SessionSummary.ofSession(_a), sb = SessionSummary.ofSession(_b);
    final rows = <(String, double?, double?, int)>[
      ('Lateral inicial (°)', sa?.initial?.lateral, sb?.initial?.lateral, 2),
      ('Lateral final (°)', sa?.last?.lateral, sb?.last?.lateral, 2),
      ('Frontal inicial (°)', sa?.initial?.frontal, sb?.initial?.frontal, 2),
      ('Frontal final (°)', sa?.last?.frontal, sb?.last?.frontal, 2),
      ('Δ final vs ref. (°)', sa?.finalDeltaRef, sb?.finalDeltaRef, 2),
      ('Δ máx. vs ref. (°)', sa?.deltaRef?.max, sb?.deltaRef?.max, 2),
      ('Lateral σ (°)', sa?.lateral?.std, sb?.lateral?.std, 3),
      ('Pico acel. lineal (m/s²)', sa?.linMagnitude?.max, sb?.linMagnitude?.max, 3),
      ('Giro máx. (rad/s)', sa?.gyroMagnitude?.max, sb?.gyroMagnitude?.max, 4),
      ('Duración activa (s)', sa?.activeSeconds, sb?.activeSeconds, 0),
    ];
    final between = sa?.last == null || sb?.last == null
        ? null
        : angleBetween(gravityDirection(sa!.last!.lateral, sa.last!.frontal),
            gravityDirection(sb!.last!.lateral, sb.last!.frontal));
    final sameTree = _a.treeId == _b.treeId;
    final sameRef = _a.calibration['at'] == _b.calibration['at'];
    final samePlacement = _a.conditions['placement'] != null &&
        _a.conditions['placement'] == _b.conditions['placement'];

    return Scaffold(
      appBar: AppBar(title: const Text('Comparar sesiones')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('A', style: Theme.of(context).textTheme.labelLarge),
        _picker(_a, (v) => _a = v),
        Text('B', style: Theme.of(context).textTheme.labelLarge),
        _picker(_b, (v) => _b = v),
        const SizedBox(height: 8),
        if (!sameTree)
          const Notice('Las sesiones son de árboles distintos.', warning: true)
        else if (!sameRef && !samePlacement)
          const Notice('Las sesiones usan referencias y colocaciones distintas: los ángulos absolutos '
              'solo son comparables si el teléfono se colocó en el mismo soporte.', icon: Icons.warning_amber),
        if (between != null)
          StatTile('Diferencia angular entre las inclinaciones finales', fmt(between, 2), unit: '°'),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('')),
                DataColumn(label: Text('A'), numeric: true),
                DataColumn(label: Text('B'), numeric: true),
                DataColumn(label: Text('B − A'), numeric: true),
              ],
              rows: [
                for (final (label, a, b, dg) in rows)
                  DataRow(cells: [
                    DataCell(Text(label)),
                    DataCell(Text(fmt(a, dg))),
                    DataCell(Text(fmt(b, dg))),
                    DataCell(Text(a == null || b == null ? '—' : fmt(b - a, dg))),
                  ]),
                DataRow(cells: [
                  const DataCell(Text('Calidad')),
                  DataCell(Text(sa?.quality.name ?? _a.status.name)),
                  DataCell(Text(sb?.quality.name ?? _b.status.name)),
                  const DataCell(Text('')),
                ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
