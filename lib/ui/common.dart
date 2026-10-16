import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../analysis/alerts.dart';
import '../analysis/summary.dart';
import '../app.dart';
import '../data/models.dart';
import '../sensors/tilt.dart';
import 'history_page.dart';

/// Carga datos con [load] y los vuelve a cargar cuando cambia la base de
/// datos o cambian [keys]. Muestra estados de carga y de error.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final List<Object?> keys;
  const Loader({super.key, required this.load, required this.builder, this.keys = const []});

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future = widget.load();

  void _reload() {
    final f = widget.load();
    setState(() {
      _future = f;
    });
  }

  @override
  void initState() {
    super.initState();
    repo.changes.addListener(_reload);
  }

  @override
  void didUpdateWidget(Loader<T> old) {
    super.didUpdateWidget(old);
    if (!_sameKeys(old.keys, widget.keys)) _reload();
  }

  bool _sameKeys(List<Object?> a, List<Object?> b) =>
      a.length == b.length && Iterable.generate(a.length).every((i) => a[i] == b[i]);

  @override
  void dispose() {
    repo.changes.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return MessageView(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar los datos',
              text: '${snap.error}',
              action: TextButton(onPressed: _reload, child: const Text('Reintentar')),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return widget.builder(context, snap.data as T);
        },
      );
}

class MessageView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;
  const MessageView({super.key, required this.icon, required this.title, this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: t.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (text != null) ...[
            const SizedBox(height: 6),
            Text(text!, style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ]),
      );
}

/// Aviso con icono y color (información, advertencia o error).
class Notice extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool warning;
  const Notice(this.text, {super.key, this.icon = Icons.info_outline, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      color: warning ? c.errorContainer : c.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: warning ? c.onErrorContainer : c.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: warning ? c.onErrorContainer : c.onSecondaryContainer))),
        ]),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label, value;
  final String? unit;
  const StatTile(this.label, this.value, {super.key, this.unit});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.labelMedium, maxLines: 2),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: t.headlineSmall),
            if (unit != null) TextSpan(text: ' $unit', style: t.bodySmall),
          ])),
        ]),
      ),
    );
  }
}

/// Fila de tarjetas de igual ancho.
class StatRow extends StatelessWidget {
  final List<Widget> children;
  const StatRow(this.children, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final c in children) Expanded(child: c)],
      );
}

Future<bool> confirm(BuildContext context, String title, String text,
    {String action = 'Eliminar'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

void snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

String durationLabel(Duration? d) {
  if (d == null) return '—';
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h h $m min' : m > 0 ? '$m min $s s' : '$s s';
}

class QualityChip extends StatelessWidget {
  final Session session;
  const QualityChip(this.session, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final q = SessionSummary.ofSession(session)?.quality;
    final (label, bg) = switch (session.status) {
      SessionStatus.running => ('En curso', c.tertiaryContainer),
      SessionStatus.paused => ('En pausa', c.tertiaryContainer),
      SessionStatus.interrupted => ('Incompleta', c.errorContainer),
      SessionStatus.completed => switch (q) {
          Quality.buena => ('Buena calidad', c.primaryContainer),
          Quality.revisar => ('Revisar', c.tertiaryContainer),
          _ => ('Incompleta', c.errorContainer),
        },
    };
    return Chip(
      label: Text(label),
      backgroundColor: bg,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class SessionTile extends StatelessWidget {
  final Session session;
  final String? treeCode;
  const SessionTile(this.session, {super.key, this.treeCode});

  @override
  Widget build(BuildContext context) {
    final sum = SessionSummary.ofSession(session);
    return Card(
      child: ListTile(
        title: Text(treeCode ?? 'Sesión #${session.id}'),
        subtitle: Text('${dateLabel(session.startedAt)} · ${durationLabel(session.duration)}'
            '${sum?.finalDeltaRef == null ? '' : ' · Δ ref ${fmt(sum!.finalDeltaRef, 2)}°'}'),
        trailing: QualityChip(session),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => SessionDetailPage(sessionId: session.id!))),
      ),
    );
  }
}

/// Gráfica de líneas sencilla. [xLabel] da formato a las etiquetas del eje x.
class SeriesChart extends StatelessWidget {
  final List<({String label, Color color, List<FlSpot> spots})> series;
  final String Function(double x) xLabel;
  final String unit;
  final double height;
  const SeriesChart({
    super.key,
    required this.series,
    required this.xLabel,
    required this.unit,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final all = series.expand((s) => s.spots).toList();
    if (all.isEmpty) {
      return SizedBox(height: height, child: const Center(child: Text('Sin datos para graficar')));
    }
    final xs = all.map((s) => s.x), ys = all.map((s) => s.y);
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    var minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final pad = math.max((maxY - minY) * 0.1, 0.05);
    minY -= pad;
    maxY += pad;
    final small = t.textTheme.labelSmall;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, children: [
        for (final s in series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 3, color: s.color),
            const SizedBox(width: 4),
            Text('${s.label} ($unit)', style: small),
          ]),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: height,
        child: LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: minX,
            maxX: maxX == minX ? minX + 1 : maxX,
            minY: minY,
            maxY: maxY,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: t.colorScheme.outlineVariant, strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta, child: Text(fmt(v, 2), style: small)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: maxX == minX ? 1 : (maxX - minX) / 3,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta, child: Text(xLabel(v), style: small)),
                ),
              ),
            ),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              for (final s in series)
                LineChartBarData(
                  spots: s.spots,
                  color: s.color,
                  barWidth: 2,
                  dotData: FlDotData(show: s.spots.length < 30),
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// Nivel de burbuja: representa la variación respecto a la referencia.
/// El centro es la referencia; el borde equivale a [rangeDeg].
class TiltIndicator extends StatelessWidget {
  final double lateral, frontal, rangeDeg;
  final double size;
  const TiltIndicator(
      {super.key, required this.lateral, required this.frontal, this.rangeDeg = 5, this.size = 180});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Indicador de orientación: lateral ${fmt(lateral)} grados, '
            'frontal ${fmt(frontal)} grados respecto a la referencia',
        child: CustomPaint(
          size: Size.square(size),
          painter: _TiltPainter(lateral, frontal, rangeDeg, Theme.of(context).colorScheme),
        ),
      );
}

class _TiltPainter extends CustomPainter {
  final double lateral, frontal, range;
  final ColorScheme c;
  _TiltPainter(this.lateral, this.frontal, this.range, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final line = Paint()
      ..color = c.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, r, Paint()..color = c.surfaceContainerHighest);
    canvas.drawCircle(center, r, line);
    canvas.drawCircle(center, r / 2, line);
    canvas.drawLine(center - Offset(r, 0), center + Offset(r, 0), line);
    canvas.drawLine(center - Offset(0, r), center + Offset(0, r), line);
    var o = Offset(lateral / range * r, -frontal / range * r);
    final outside = o.distance > r - 10;
    if (outside) o = o / o.distance * (r - 10);
    canvas.drawCircle(center + o, 10, Paint()..color = outside ? c.error : c.primary);
  }

  @override
  bool shouldRepaint(_TiltPainter old) =>
      old.lateral != lateral || old.frontal != frontal || old.c != c;
}

/// Fotografías: tomar con la cámara o elegir de la galería. Se copian a la
/// carpeta privada de la app para que no dependan de la galería.
class PhotoField extends StatelessWidget {
  final List<String> photos;
  final ValueChanged<List<String>> onChanged;
  const PhotoField({super.key, required this.photos, required this.onChanged});

  Future<void> _add(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tomar fotografía'),
              onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, maxWidth: 1920, imageQuality: 85);
      if (picked == null) return;
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'photos'));
      await dir.create(recursive: true);
      final dest = p.join(dir.path,
          '${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}');
      await File(picked.path).copy(dest);
      onChanged([...photos, dest]);
    } catch (e) {
      if (context.mounted) snack(context, 'No se pudo obtener la fotografía: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final path in photos)
          Stack(children: [
            PhotoThumb(path),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                tooltip: 'Quitar fotografía',
                icon: const Icon(Icons.close, size: 16),
                // ponytail: el archivo queda en disco; limpiar huérfanos si ocupa espacio
                onPressed: () => onChanged([...photos]..remove(path)),
              ),
            ),
          ]),
        SizedBox(
          width: 96,
          height: 96,
          child: OutlinedButton(
            onPressed: () => _add(context),
            child: const Icon(Icons.add_a_photo_outlined),
          ),
        ),
      ]);
}

class PhotoThumb extends StatelessWidget {
  final String path;
  final double size;
  const PhotoThumb(this.path, {super.key, this.size = 96});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => Dialog(
            child: InteractiveViewer(
                child: Image.file(File(path),
                    errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(24), child: Text('Fotografía no encontrada')))),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 2).round(),
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      );
}

/// Campo de selección con opciones fijas.
class ChoiceField extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  const ChoiceField(
      {super.key, required this.label, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: options.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: onChanged,
        ),
      );
}
