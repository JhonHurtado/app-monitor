import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../sensors/recorder.dart';
import '../sensors/tilt.dart';
import 'common.dart';
import 'history_page.dart';

class LiveSessionPage extends StatefulWidget {
  final int sessionId;
  final String treeCode;
  final Calibration reference;
  final double hz;
  final bool useLinear, useGyro;
  final Duration previouslyActive;

  const LiveSessionPage({
    super.key,
    required this.sessionId,
    required this.treeCode,
    required this.reference,
    required this.hz,
    this.useLinear = true,
    this.useGyro = true,
    this.previouslyActive = Duration.zero,
  });

  @override
  State<LiveSessionPage> createState() => _LiveSessionPageState();
}

class _LiveSessionPageState extends State<LiveSessionPage> with WidgetsBindingObserver {
  late final SessionRecorder rec = SessionRecorder(
    repo: repo,
    sessionId: widget.sessionId,
    reference: widget.reference,
    hz: widget.hz,
    src: sensors,
    useLinear: widget.useLinear,
    useGyro: widget.useGyro,
    previouslyActive: widget.previouslyActive,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    rec.addListener(_changed);
    rec.start();
    sensors.keepScreenOn(true).catchError((_) {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Sin servicio en segundo plano: al salir de la app la sesión se pausa y
  /// se guardan los datos.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && rec.state == RecState.recording) {
      rec.pause();
      rec.warning = 'Sesión pausada al salir de la aplicación.';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    rec.removeListener(_changed);
    rec.dispose();
    sensors.keepScreenOn(false).catchError((_) {});
    super.dispose();
  }

  Future<void> _finish() async {
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Finalizar sesión'),
        content: TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir midiendo')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Finalizar')),
        ],
      ),
    );
    if (ok != true) return;
    final existing = (await repo.session(widget.sessionId))?.notes;
    final text = [?existing, if (notes.text.trim().isNotEmpty) notes.text.trim()].join('\n');
    await rec.finish(notes: text.isEmpty ? null : text);
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => SessionDetailPage(sessionId: widget.sessionId)));
  }

  @override
  Widget build(BuildContext context) {
    final l = rec.live;
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final recording = rec.state == RecState.recording;
    final secs = rec.active.inSeconds;
    final t0 = rec.recent.isEmpty ? null : rec.recent.first.t;
    double x(DateTime d) => d.difference(t0!).inMilliseconds / 1000;

    return PopScope(
      canPop: rec.state != RecState.recording,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm(context, 'Salir de la sesión',
            'La sesión quedará en pausa con los datos guardados. Podrás reanudarla o finalizarla desde el historial.',
            action: 'Salir')) {
          await rec.pause();
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Midiendo · ${widget.treeCode}')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Icon(Icons.circle, size: 14, color: recording ? c.error : c.outline),
            const SizedBox(width: 6),
            Text(recording ? 'Grabando' : rec.state == RecState.paused ? 'En pausa' : 'Finalizada',
                style: t.titleMedium),
            const Spacer(),
            Text('${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}',
                style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          Text('${rec.saved} muestras guardadas · ${rec.pending} en memoria · ${widget.hz.round()} Hz'
              '${rec.invalid > 0 ? ' · ${rec.invalid} inválidas' : ''}',
              style: t.bodySmall),
          if (rec.error != null) Notice(rec.error!, warning: true),
          if (rec.warning != null) Notice(rec.warning!, icon: Icons.warning_amber),
          if (l?.tilt.offAxis ?? false)
            const Notice('El teléfono no está en vertical: los ejes lateral y frontal no son fiables.',
                warning: true),
          const SizedBox(height: 12),
          if (l == null)
            const SizedBox(
                height: 180,
                child: Center(child: Text('Esperando lecturas del acelerómetro…')))
          else ...[
            Center(child: TiltIndicator(lateral: l.deltaLateral, frontal: l.deltaFrontal)),
            Center(child: Text('Borde = ±5° respecto a la referencia', style: t.bodySmall)),
            const SizedBox(height: 8),
            StatRow([
              StatTile('Δ lateral', fmt(l.deltaLateral, 2), unit: '°'),
              StatTile('Δ frontal', fmt(l.deltaFrontal, 2), unit: '°'),
              StatTile('Δ total vs ref.', fmt(l.deltaRef, 2), unit: '°'),
            ]),
            StatRow([
              StatTile('Lateral', fmt(l.tilt.lateral, 2), unit: '°'),
              StatTile('Frontal', fmt(l.tilt.frontal, 2), unit: '°'),
              StatTile('Desde vertical', fmt(l.tilt.fromVertical, 2), unit: '°'),
            ]),
            StatRow([
              StatTile('Acel. lineal', l.lin == null ? 'N/D' : fmt(l.lin!.norm, 2), unit: l.lin == null ? null : 'm/s²'),
              StatTile('Pico lineal', widget.useLinear ? fmt(rec.peakLin, 2) : 'N/D', unit: widget.useLinear ? 'm/s²' : null),
              StatTile('Giro', l.gyro == null ? 'N/D' : fmt(l.gyro!.norm, 3), unit: l.gyro == null ? null : 'rad/s'),
            ]),
            const SectionTitle('Últimos 30 s'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SeriesChart(
                  unit: '°',
                  height: 160,
                  xLabel: (v) => '${v.round()} s',
                  series: [
                    (label: 'Δ lateral', color: c.primary, spots: [for (final p in rec.recent) FlSpot(x(p.t), p.dLateral)]),
                    (label: 'Δ frontal', color: c.tertiary, spots: [for (final p in rec.recent) FlSpot(x(p.t), p.dFrontal)]),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: rec.state == RecState.finished ? null : (recording ? rec.pause : rec.start),
                icon: Icon(recording ? Icons.pause : Icons.play_arrow),
                label: Text(recording ? 'Pausar' : 'Reanudar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: rec.state == RecState.finished ? null : _finish,
                icon: const Icon(Icons.stop),
                label: const Text('Finalizar'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
