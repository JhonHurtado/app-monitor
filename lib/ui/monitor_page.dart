import 'dart:async';

import 'package:flutter/material.dart';

import '../analysis/alerts.dart';
import '../app.dart';
import '../data/models.dart';
import '../sensors/device.dart';
import '../sensors/recorder.dart';
import '../sensors/tilt.dart';
import 'common.dart';
import 'live_session_page.dart';
import 'trees_page.dart';

const measurementWarning =
    'La app mide la orientación del TELÉFONO, no la del árbol. Para obtener '
    'mediciones comparables, fija el teléfono siempre en el mismo soporte o '
    'superficie de referencia sobre el tronco, en vertical (retrato). El '
    'movimiento de la mano, las vibraciones y el viento alteran las lecturas.';

class MonitorPage extends StatelessWidget {
  const MonitorPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Monitoreo')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Nueva sesión de medición'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SessionSetupPage())),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.speed),
            label: const Text('Ver lecturas en vivo'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const LiveSensorsPage())),
          ),
          Loader(
            load: () => repo.sessions().then((l) => l.where((s) => s.status == SessionStatus.paused).toList()),
            builder: (context, paused) => paused.isEmpty
                ? const SizedBox.shrink()
                : Column(children: [
                    const SectionTitle('Sesiones en pausa'),
                    for (final s in paused) SessionTile(s, treeCode: 'Sesión #${s.id}'),
                  ]),
          ),
          const SectionTitle('Sensores del dispositivo'),
          const SensorAvailability(),
          const SectionTitle('Sistema de coordenadas'),
          const Notice(
              'Ejes de Android: x hacia la derecha de la pantalla, y hacia la parte superior, '
              'z saliendo de la pantalla. Lateral (+) = parte superior inclinada a la derecha. '
              'Frontal (+) = pantalla mirando hacia arriba. Ángulos en grados.',
              icon: Icons.explore_outlined),
          const Notice(measurementWarning, icon: Icons.warning_amber),
        ]),
      );
}

class SensorAvailability extends StatelessWidget {
  const SensorAvailability({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<List<DeviceSensor>>(
        future: sensors.list(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Notice('No se pudo consultar los sensores del dispositivo: ${snap.error}',
                warning: true);
          }
          if (!snap.hasData) return const LinearProgressIndicator();
          final list = snap.data!;
          final c = Theme.of(context).colorScheme;
          return Card(
            child: Column(children: [
              for (final k in SensorKind.values)
                Builder(builder: (context) {
                  final s = list.where((s) => s.type == k.androidType).firstOrNull;
                  return ListTile(
                    leading: Icon(s == null ? Icons.cancel_outlined : Icons.check_circle,
                        color: s == null ? c.error : c.primary),
                    title: Text('${k.label} ${s == null ? '· No disponible' : ''}'),
                    subtitle: Text(s == null
                        ? k.role
                        : '${s.name} (${s.vendor})'
                            '${s.maxHz == null ? '' : ' · hasta ${fmt(s.maxHz, 0)} Hz'}'
                            ' · resolución ${s.resolution.toStringAsPrecision(2)} ${k.unit}\n${k.role}'),
                    isThreeLine: s != null,
                  );
                }),
              ListTile(
                dense: true,
                title: Text('Total de sensores reportados por el dispositivo: ${list.length}'),
              ),
            ]),
          );
        },
      );
}

/// Escucha uno o más sensores mientras la pantalla está visible y la app en
/// primer plano. Los valores se leen periódicamente para no redibujar con
/// cada evento.
mixin _SensorListening<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  final _subs = <StreamSubscription>[];
  Timer? _refresh;
  var _dirty = false;

  Map<String, SensorStream> get streams;
  Duration get period => periodFor(20);
  void onReading(String key, Reading r);
  void onSensorError(String key, Object error);

  void _listen() {
    _cancel();
    for (final e in streams.entries) {
      _subs.add(e.value(period).listen((r) {
        onReading(e.key, r);
        _dirty = true;
      }, onError: (Object err) {
        onSensorError(e.key, err);
        _dirty = true;
      }));
    }
    // Redibujar a ~7 Hz y solo si llegaron datos nuevos.
    _refresh = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (mounted && _dirty) setState(() => _dirty = false);
    });
  }

  void _cancel() {
    _refresh?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _listen();
    } else if (state == AppLifecycleState.paused) {
      _cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    super.dispose();
  }
}

class LiveSensorsPage extends StatefulWidget {
  const LiveSensorsPage({super.key});

  @override
  State<LiveSensorsPage> createState() => _LiveSensorsPageState();
}

class _LiveSensorsPageState extends State<LiveSensorsPage>
    with WidgetsBindingObserver, _SensorListening {
  final _values = <String, Vec3>{};
  final _errors = <String, String>{};
  final _filter = GravityFilter();

  @override
  Map<String, SensorStream> get streams => {
        'acc': sensors.accelerometer,
        'lin': sensors.linearAcceleration,
        'gyro': sensors.gyroscope,
        'mag': sensors.magnetometer,
      };

  @override
  void onReading(String key, Reading r) {
    _values[key] = r.v;
    if (key == 'acc') {
      final g = _filter.add(r.v, r.t);
      if (g != null) _values['grav'] = g;
    }
  }

  @override
  void onSensorError(String key, Object error) =>
      _errors[key] = '$error'.contains('NO_SENSOR') ? 'No disponible en este dispositivo' : 'Error: $error';

  Widget _card(String title, String key, String unit, String help, {int digits = 3}) {
    final v = _values[key];
    final err = _errors[key];
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$title ($unit)', style: t.titleSmall),
          Text(help, style: t.bodySmall),
          const SizedBox(height: 6),
          if (err != null)
            Text(err, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (v == null)
            const Text('Esperando datos…')
          else
            Text('x ${fmt(v.x, digits)}   y ${fmt(v.y, digits)}   z ${fmt(v.z, digits)}   |v| ${fmt(v.norm, digits)}',
                style: t.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _values['grav'];
    final tilt = g == null ? null : Tilt.fromGravity(g);
    return Scaffold(
      appBar: AppBar(title: const Text('Lecturas en vivo')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _card('Acelerómetro', 'acc', 'm/s²', 'Aceleración total, incluye la gravedad.'),
        _card('Gravedad estimada', 'grav', 'm/s²', 'Filtro paso bajo del acelerómetro (τ = 0,5 s).'),
        _card('Aceleración lineal', 'lin', 'm/s²', 'Sin gravedad (sensor virtual de Android).'),
        _card('Giroscopio', 'gyro', 'rad/s', 'Velocidad angular.'),
        _card('Magnetómetro', 'mag', 'µT', 'Solo informativo; no se usa en las mediciones.', digits: 1),
        if (tilt != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                TiltIndicator(lateral: tilt.lateral, frontal: tilt.frontal, rangeDeg: 30, size: 110),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                      'Lateral ${fmt(tilt.lateral)}°\nFrontal ${fmt(tilt.frontal)}°\n'
                      'Desde la vertical ${fmt(tilt.fromVertical)}°'
                      '${tilt.offAxis ? '\n\nEl teléfono no está en vertical.' : ''}',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Preparación de una sesión: árbol, condiciones y referencia angular.
class SessionSetupPage extends StatefulWidget {
  final int? treeId;
  const SessionSetupPage({super.key, this.treeId});

  @override
  State<SessionSetupPage> createState() => _SessionSetupPageState();
}

const windOptions = ['Calma', 'Brisa', 'Viento moderado', 'Viento fuerte', 'No registrado'];

class _SessionSetupPageState extends State<SessionSetupPage>
    with WidgetsBindingObserver, _SensorListening {
  late int? _treeId = widget.treeId;
  var _hz = 20.0;
  String? _wind;
  final _placement = TextEditingController();
  final _notes = TextEditingController();
  final _filter = GravityFilter();
  Tilt? _tilt;
  String? _accError;
  Calibration? _calibration;
  var _calibrating = false, _starting = false;
  Set<SensorKind>? _available;
  String? _availabilityError;
  List<Tree> _trees = [];
  List<Session> _previous = [];
  bool _reuse = false;
  Session? _reuseFrom;

  @override
  Map<String, SensorStream> get streams => {'acc': sensors.accelerometer};

  @override
  void onReading(String key, Reading r) {
    final g = _filter.add(r.v, r.t);
    if (g != null) _tilt = Tilt.fromGravity(g);
  }

  @override
  void onSensorError(String key, Object error) => _accError = '$error';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _available = await sensors.available();
    } catch (e) {
      _availabilityError = '$e';
    }
    _trees = await repo.trees();
    if (_treeId != null && !_trees.any((t) => t.id == _treeId)) _treeId = null;
    await _loadPrevious();
    if (mounted) setState(() {});
  }

  /// Sesiones anteriores del árbol: permiten reutilizar su referencia y
  /// precargan la colocación usada, para favorecer mediciones comparables.
  Future<void> _loadPrevious() async {
    _previous = _treeId == null ? [] : await repo.sessions(treeId: _treeId);
    _reuseFrom = _previous.firstOrNull;
    if (_reuse && _reuseFrom == null) _reuse = false;
    final last = _previous.firstOrNull?.conditions['placement'] as String?;
    if (_placement.text.isEmpty && last != null) _placement.text = last;
  }

  Future<void> _calibrate() async {
    setState(() => _calibrating = true);
    final c = await calibrate(sensors);
    if (!mounted) return;
    setState(() {
      _calibrating = false;
      _calibration = c;
    });
    if (c == null) snack(context, 'No se recibieron suficientes lecturas del acelerómetro.');
  }

  Calibration? get _reference => _reuse && _reuseFrom != null
      ? Calibration.fromJson(_reuseFrom!.calibration).reusedFrom(_reuseFrom!.id!)
      : _calibration;

  Future<void> _start() async {
    final ref = _reference!;
    setState(() => _starting = true);
    final av = _available ?? {};
    final useLinear = av.contains(SensorKind.linearAcceleration);
    final useGyro = av.contains(SensorKind.gyroscope);
    final id = await repo.createSession(Session(
      treeId: _treeId!,
      startedAt: DateTime.now(),
      samplingHz: _hz,
      calibration: ref.toJson(),
      conditions: {
        if (_placement.text.trim().isNotEmpty) 'placement': _placement.text.trim(),
        'wind': ?_wind,
      },
      sensors: [
        'accelerometer',
        if (useLinear) 'linear_acceleration',
        if (useGyro) 'gyroscope',
      ],
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    ));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LiveSessionPage(
          sessionId: id,
          treeCode: _trees.firstWhere((t) => t.id == _treeId).code,
          reference: ref,
          hz: _hz,
          useLinear: useLinear,
          useGyro: useGyro,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accMissing = _accError != null ||
        (_available != null && !_available!.contains(SensorKind.accelerometer));
    final ref = _reference;
    final canStart = !accMissing && _treeId != null && ref != null && !_starting && !_calibrating;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva sesión')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (accMissing)
          Notice(
              'El acelerómetro no está disponible en este dispositivo; no es posible medir la inclinación.'
              '${_accError == null ? '' : '\n$_accError'}',
              warning: true)
        else if (_availabilityError != null)
          Notice('No se pudo verificar la lista de sensores: $_availabilityError', warning: true),
        const Notice(measurementWarning, icon: Icons.warning_amber),
        const SectionTitle('1. Árbol y condiciones'),
        if (_trees.isEmpty)
          Card(
            child: ListTile(
              title: const Text('No hay árboles registrados'),
              trailing: FilledButton(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const TreeFormPage()));
                  _init();
                },
                child: const Text('Registrar'),
              ),
            ),
          )
        else
          DropdownButtonFormField<int>(
            key: ValueKey(_trees.length),
            initialValue: _treeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Árbol *'),
            items: [for (final t in _trees) DropdownMenuItem(value: t.id, child: Text(t.code))],
            onChanged: (v) async {
              _treeId = v;
              await _loadPrevious();
              setState(() {});
            },
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _placement,
          decoration: const InputDecoration(
              labelText: 'Colocación / soporte',
              hintText: 'Ej.: soporte fijo, cara norte, 1,30 m de altura'),
        ),
        const SizedBox(height: 12),
        ChoiceField(label: 'Viento', options: windOptions, value: _wind, onChanged: (v) => setState(() => _wind = v)),
        Text('Frecuencia de muestreo', style: t.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<double>(
          segments: [for (final hz in samplingOptions) ButtonSegment(value: hz, label: Text('${hz.round()} Hz'))],
          selected: {_hz},
          onSelectionChanged: (s) => setState(() => _hz = s.first),
        ),
        const SizedBox(height: 4),
        Text('Mayor frecuencia = más datos y más consumo de batería.', style: t.bodySmall),
        const SizedBox(height: 12),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Observaciones (opcional)')),
        const SectionTitle('2. Referencia angular'),
        if (_previous.isNotEmpty)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reutilizar la referencia de una sesión anterior'),
            subtitle: const Text('Para medir la variación respecto a una línea base. '
                'Requiere el mismo soporte y colocación.'),
            value: _reuse,
            onChanged: (v) => setState(() => _reuse = v),
          ),
        if (_reuse && _reuseFrom != null)
          DropdownButtonFormField<int>(
            initialValue: _reuseFrom!.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sesión de referencia'),
            items: [
              for (final s in _previous)
                DropdownMenuItem(value: s.id, child: Text('${dateLabel(s.startedAt)} (#${s.id})')),
            ],
            onChanged: (id) => setState(() => _reuseFrom = _previous.firstWhere((s) => s.id == id)),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text('Fija el teléfono en su soporte, suéltalo y pulsa «Calibrar». '
                    'Se promedian 2 s de lecturas.', style: t.bodyMedium),
                const SizedBox(height: 12),
                if (_tilt != null)
                  Row(children: [
                    TiltIndicator(lateral: _tilt!.lateral, frontal: _tilt!.frontal, rangeDeg: 30, size: 100),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Text('Actual\nLateral ${fmt(_tilt!.lateral)}°\nFrontal ${fmt(_tilt!.frontal)}°',
                            style: t.titleMedium)),
                  ]),
                if (_tilt?.offAxis ?? false)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Notice('El teléfono no está en vertical: colócalo en retrato sobre el tronco.',
                        warning: true),
                  ),
                if (_calibration != null) ...[
                  const SizedBox(height: 12),
                  Text(
                      'Referencia: lateral ${fmt(_calibration!.tilt.lateral, 2)}°, '
                      'frontal ${fmt(_calibration!.tilt.frontal, 2)}° '
                      '(${_calibration!.samples} lecturas, σ = ${fmt(_calibration!.stdDeg, 2)}°)',
                      style: t.bodyMedium),
                  if (!_calibration!.isStable)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Notice('El teléfono se movió durante la calibración. Repítela sin tocarlo.',
                          warning: true),
                    ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: accMissing || _calibrating ? null : _calibrate,
                  icon: _calibrating
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.center_focus_strong),
                  label: Text(_calibrating
                      ? 'Calibrando…'
                      : _calibration == null
                          ? 'Calibrar'
                          : 'Repetir calibración'),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: canStart ? _start : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar sesión'),
        ),
        if (!canStart && !accMissing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                _treeId == null ? 'Selecciona un árbol.' : ref == null ? 'Calibra la referencia.' : '',
                style: t.bodySmall,
                textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}
