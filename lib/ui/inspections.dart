import 'package:flutter/material.dart';

import '../analysis/alerts.dart';
import '../app.dart';
import '../data/models.dart';
import 'common.dart';

/// Campos de inspección visual: (etiqueta, opciones, lector).
final inspectionFields = <(String, List<String>, String? Function(Inspection))>[
  ('Hojas', ['Normales', 'Amarillentas o decoloradas', 'Escasas o caída anormal', 'Secas', 'Sin hojas (estacional)', 'No evaluado'], (i) => i.leafCondition),
  ('Ramas', ['Sin ramas secas', 'Algunas ramas secas', 'Muchas ramas secas', 'Ramas rotas o colgantes', 'No evaluado'], (i) => i.branchCondition),
  ('Tronco', ['Sin daños visibles', 'Heridas o cortes', 'Grietas', 'Desprendimiento de corteza', 'Cavidades', 'No evaluado'], (i) => i.trunkCondition),
  ('Copa', ['Sin cambios aparentes', 'Más rala', 'Asimétrica o deformada', 'Pérdida de volumen', 'No evaluado'], (i) => i.crownCondition),
  ('Hongos o plagas', ['No observados', 'Posibles hongos', 'Posibles plagas', 'Posibles hongos y plagas', 'No evaluado'], (i) => i.pests),
  ('Inclinación visible', ['No apreciable', 'Leve', 'Notable', 'Cambio respecto a la anterior', 'No evaluado'], (i) => i.visibleInclination),
];

String inspectionSummary(Inspection i) => [
      for (final (label, _, get) in inspectionFields)
        if (get(i) != null) '$label: ${get(i)}',
    ].join(' · ');

class InspectionFormPage extends StatefulWidget {
  final int treeId;
  final Inspection? inspection;
  const InspectionFormPage({super.key, required this.treeId, this.inspection});

  @override
  State<InspectionFormPage> createState() => _InspectionFormPageState();
}

class _InspectionFormPageState extends State<InspectionFormPage> {
  late final i = widget.inspection;
  late final List<String?> _values = [for (final f in inspectionFields) i == null ? null : f.$3(i!)];
  late final _obs = TextEditingController(text: i?.observations);
  late List<String> _photos = [...?i?.photos];

  Future<void> _save() async {
    try {
      await repo.saveInspection(Inspection(
        id: i?.id,
        treeId: widget.treeId,
        createdAt: i?.createdAt ?? DateTime.now(),
        leafCondition: _values[0],
        branchCondition: _values[1],
        trunkCondition: _values[2],
        crownCondition: _values[3],
        pests: _values[4],
        visibleInclination: _values[5],
        observations: _obs.text.trim().isEmpty ? null : _obs.text.trim(),
        photos: _photos,
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, 'No se pudo guardar: $e');
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Eliminar inspección',
        'Se eliminará la inspección del ${dateLabel(i!.createdAt)}. Esta acción no se puede deshacer.')) {
      return;
    }
    await repo.deleteInspection(i!.id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(i == null ? 'Nueva inspección' : 'Inspección ${dateLabel(i!.createdAt)}'),
          actions: [
            if (i != null)
              IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Notice('Registro de observación visual. No constituye un diagnóstico.'),
          const SizedBox(height: 12),
          for (var k = 0; k < inspectionFields.length; k++)
            ChoiceField(
              label: inspectionFields[k].$1,
              options: inspectionFields[k].$2,
              value: _values[k],
              onChanged: (v) => setState(() => _values[k] = v),
            ),
          TextField(
            controller: _obs,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Observaciones libres'),
          ),
          const SectionTitle('Fotografías de seguimiento'),
          PhotoField(photos: _photos, onChanged: (p) => setState(() => _photos = p)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Guardar')),
        ]),
      );
}

/// Compara dos inspecciones del mismo árbol, lado a lado.
class InspectionComparePage extends StatefulWidget {
  final List<Inspection> inspections; // más reciente primero
  const InspectionComparePage({super.key, required this.inspections});

  @override
  State<InspectionComparePage> createState() => _InspectionComparePageState();
}

class _InspectionComparePageState extends State<InspectionComparePage> {
  late Inspection _a = widget.inspections[1], _b = widget.inspections[0];

  Widget _picker(Inspection value, ValueChanged<Inspection> onChanged) =>
      DropdownButton<Inspection>(
        value: value,
        isExpanded: true,
        items: [
          for (final i in widget.inspections)
            DropdownMenuItem(value: i, child: Text(dateLabel(i.createdAt))),
        ],
        onChanged: (v) => setState(() => onChanged(v!)),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rows = [
      for (final (label, _, get) in inspectionFields) (label, get(_a), get(_b)),
      ('Observaciones', _a.observations, _b.observations),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Comparar inspecciones')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: _picker(_a, (v) => _a = v)),
          const SizedBox(width: 16),
          Expanded(child: _picker(_b, (v) => _b = v)),
        ]),
        const SizedBox(height: 8),
        for (final (label, a, b) in rows)
          Card(
            color: a != b ? t.colorScheme.tertiaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a != b ? '$label · cambió' : label, style: t.textTheme.labelLarge),
                const SizedBox(height: 4),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(a ?? '—')),
                  const SizedBox(width: 16),
                  Expanded(child: Text(b ?? '—')),
                ]),
              ]),
            ),
          ),
        const SectionTitle('Fotografías'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final i in [_a, _b])
            Expanded(
              child: i.photos.isEmpty
                  ? const Text('Sin fotografías')
                  : Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final p in i.photos) PhotoThumb(p, size: 140),
                    ]),
            ),
        ]),
      ]),
    );
  }
}
