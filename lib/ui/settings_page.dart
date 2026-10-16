import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../sensors/tilt.dart';
import 'common.dart';

/// Umbrales de alerta configurables. Desactivados por defecto.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Umbrales de alerta')),
        body: Loader(
            load: repo.alertSettings,
            builder: (context, cfg) => _SettingsForm(cfg)),
      );
}

class _SettingsForm extends StatefulWidget {
  final AlertSettings cfg;
  const _SettingsForm(this.cfg);

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  final _form = GlobalKey<FormState>();
  late final _angle = TextEditingController(text: _txt(widget.cfg.angleChangeDeg));
  late final _move = TextEditingController(text: _txt(widget.cfg.movementMs2));
  late final _diff = TextEditingController(text: _txt(widget.cfg.sessionDiffDeg));

  static String _txt(double? v) => v == null ? '' : fmt(v, 2);
  static double? _num(String s) =>
      s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));

  String? _validate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final v = _num(s);
    return v == null || v <= 0 ? 'Introduce un número mayor que 0 o deja vacío' : null;
  }

  Widget _field(TextEditingController c, String label, String unit, String help) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: _validate,
          decoration: InputDecoration(
              labelText: label, suffixText: unit, helperText: help, helperMaxLines: 3),
        ),
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await repo.saveAlertSettings(AlertSettings(
      angleChangeDeg: _num(_angle.text),
      movementMs2: _num(_move.text),
      sessionDiffDeg: _num(_diff.text),
    ));
    if (mounted) {
      snack(context, 'Umbrales guardados');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Notice(
              'No existen umbrales universales de seguridad para árboles. Deja los campos '
              'vacíos (alertas desactivadas) hasta que un profesional defina valores '
              'adecuados para cada caso. Las alertas solo describen el dato observado.',
              icon: Icons.warning_amber),
          const SizedBox(height: 16),
          _field(_angle, 'Variación respecto a la referencia', '°',
              'Avisa si la inclinación final de una sesión difiere de su referencia en este valor o más.'),
          _field(_move, 'Pico de aceleración lineal', 'm/s²',
              'Avisa de movimientos inusuales durante una sesión. También se usa para contar eventos de movimiento.'),
          _field(_diff, 'Diferencia entre sesiones', '°',
              'Avisa si la inclinación final difiere de la sesión anterior del mismo árbol.'),
          FilledButton(onPressed: _save, child: const Text('Guardar')),
        ]),
      );
}
