# Monitor de Árboles

Aplicación Android (Flutter) para registrar mediciones **comparables en el tiempo** de la
orientación de un teléfono fijado sobre el tronco de un árbol, junto con inspecciones
visuales manuales. Funciona sin conexión: todos los datos quedan en el teléfono (SQLite).

> La app mide la orientación del **teléfono**, no la del árbol. No diagnostica salud ni
> riesgo de caída. Para evaluar riesgo estructural debe intervenir un profesional con
> instrumentación adecuada.

## Funcionalidades

| Área | Qué hace |
|---|---|
| Árboles | Alta, edición, búsqueda, archivado y restauración. Código, especie, ubicación, GPS opcional, altura, diámetro, estado visual, observaciones y fotografías. |
| Sensores | Lista real de sensores del dispositivo mediante un canal nativo. Lecturas en vivo de acelerómetro, gravedad estimada, aceleración lineal, giroscopio y magnetómetro, con sus unidades. Indica qué sensores no están disponibles. |
| Inclinación | Calibración con el promedio de 2 s y medida de estabilidad σ. Ángulos lateral y frontal en tiempo real, variación respecto a la referencia, nivel de burbuja y posibilidad de reutilizar la referencia de una sesión anterior como línea base. |
| Sesiones | Frecuencia de 10, 20 o 50 Hz. Registro de colocación y viento. Pausa, reanudación y finalización. Escritura por lotes cada 1 s. Pausa automática al salir de la app. Recuperación de sesiones interrumpidas al arrancar. |
| Historial | Filtros por árbol, fechas e incompletas. Gráficas de evolución de inclinación y movimiento. Detalle con mínimos, máximos, medias, σ y valores inicial/final. Notas, comparación entre dos sesiones y borrado con confirmación. |
| Inspecciones | Hojas, ramas, tronco (grietas y desprendimientos), copa, hongos o plagas, inclinación visible, observaciones y fotos. Comparación lado a lado entre fechas. |
| Alertas | Aviso en vivo si la inclinación medida cambia ≥15° respecto a la calibración, más tres umbrales históricos configurables (desactivados por defecto). El aviso describe la lectura y recomienda inspección; no diagnostica riesgo de caída. |
| Exportación | `sesiones.csv`, `muestras.csv` y `datos.json` mediante el menú Compartir de Android. Se puede exportar el filtro actual o una sola sesión. |

## Requisitos e instalación

- Flutter estable 3.41 o superior, con Dart 3.11. Versión verificada: 3.41.6.
- Android SDK 36 y JDK 17 o superior. Sirve el JDK que trae Android Studio.
- Un teléfono Android 7.0 o superior (API 24) con acelerómetro.

```bash
flutter pub get
flutter test                 # pruebas automatizadas
flutter build apk --debug    # genera build/app/outputs/flutter-apk/app-debug.apk (~160 MB, todas las arquitecturas)
flutter build apk --release --split-per-abi   # ~20 MB; casi todos los teléfonos actuales usan app-arm64-v8a-release.apk
```

### Instalar en un teléfono físico

1. En el teléfono, activa **Opciones de desarrollador**: Ajustes › Acerca del teléfono, y
   pulsa 7 veces "Número de compilación". Después activa **Depuración USB**.
2. Conecta el teléfono por USB y acepta la huella RSA.
3. Comprueba que aparece con `adb devices`.
4. Instala con una de estas opciones:
   - `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
   - o directamente `flutter run` (modo depuración) o `flutter run --release`.
5. Sin cable: copia `app-debug.apk` al teléfono y ábrelo. Android pedirá permitir
   "instalar apps desconocidas" para el gestor de archivos.

Para una versión de distribución, configura una clave de firma propia antes de usar
`flutter build apk --release`. La plantilla actual firma la versión release con la clave de depuración.

### Permisos

- **Ubicación**: solo se solicita cuando el usuario pulsa "Usar ubicación actual".
- No se piden permisos de cámara ni de almacenamiento. Las fotos se obtienen con el selector
  del sistema y se copian a la carpeta privada de la app. La exportación usa el menú Compartir.

## Arquitectura

```
lib/
  main.dart                 apertura de BD, recuperación de sesiones interrumpidas
  app.dart                  tema, navegación inferior (4 pestañas), servicios globales
  sensors/
    tilt.dart               Vec3, ángulos, filtro de gravedad, calibración (lógica pura)
    device.dart             fuentes de sensores (sensors_plus + canal nativo)
    recorder.dart           grabación de sesión: suscripciones, lotes, pausa/reanudación
  analysis/
    anomaly_model.dart      ventana de 20 muestras y canal de inferencia TFLite Android
    summary.dart            estadísticas, resumen de sesión y calidad de la medición
    alerts.dart             alertas descriptivas por umbral
  data/
    db.dart                 esquema SQLite y migraciones
    models.dart             Tree, Session, Sample, Inspection, AlertSettings
    repo.dart               consultas y escrituras
    export.dart             CSV / JSON y compartir
  ui/                       pantallas (inicio, árboles, monitoreo, sesión en vivo,
                            historial, inspecciones, ajustes) y widgets comunes
android/.../MainActivity.kt canal nativo: sensores, pantalla encendida e inferencia TFLite
```

### Modelo experimental de anomalías

Durante una sesión Android, la app toma una ventana nueva cada 2 s de 20 lecturas del
acelerómetro (10 Hz), convierte m/s² a unidades de g y ejecuta
`android/app/src/main/assets/centinela_forestal.tflite` localmente. El runtime Android
incluye TensorFlow Lite Select Ops porque el modelo LSTM los requiere. Una puntuación
superior a 0,85 debe repetirse en cinco ventanas consecutivas (aprox. 10 s) antes de
mostrar la señal sostenida. Una ventana por debajo del umbral reinicia el contador. La
grabación continúa si falla la inferencia.

En paralelo e independientemente del modelo, durante la sesión se muestra un aviso
cuando la inclinación medida del teléfono cambia 15° o más respecto a la calibración.
El aviso recomienda revisar la fijación e inspeccionar el árbol profesionalmente. Es
un umbral operativo de la app, no un límite validado de seguridad estructural.

**No interpreta la puntuación como riesgo latente de caída.** `entrenamiento.py` crea
la clase sintética positiva sumando `sin(3°)` al eje X de ventanas originales. El script
valida separando árboles para evitar que ventanas del mismo árbol queden en ambos grupos;
la última validación agrupada obtuvo precision y exactitud de 0,50 para distinguir esa
transformación (azar). No contiene ejemplos etiquetados de árboles en riesgo ni caídas
reales. El entrenamiento no representa
la dinámica mecánica completa del colapso de un árbol ni está validado para decisiones de
seguridad. El resultado no reemplaza una inspección profesional, y una puntuación baja no
descarta peligro.

La lectura de sensores (`sensors/`), el cálculo (`analysis/`, `tilt.dart`), la persistencia
(`data/`) y la interfaz (`ui/`) están separados. No hay gestor de estado ni router: se usan
`setState`, `Navigator` y un `ValueNotifier` en el repositorio que avisa a las pantallas
para recargar. Se descartó la estructura por funcionalidades con capas data/domain/presentation porque
añadía carpetas y abstracciones sin beneficio para un MVP de este tamaño.

### Dependencias

`sensors_plus` (sensores), `sqflite` (SQLite), `fl_chart` (gráficas), `geolocator` (GPS),
`image_picker` (fotos), `share_plus` (exportar), `path_provider`, `path`.
En Android, la inferencia usa `tensorflow-lite` y `tensorflow-lite-select-tf-ops`.
En desarrollo: `sqflite_common_ffi` (BD en memoria para las pruebas).
Se eligió `sqflite` en lugar de Drift para evitar la generación de código. Las migraciones se
gestionan con una lista ordenada de pasos SQL en `data/db.dart`.

## Modelo de datos

Todas las fechas se guardan como milisegundos desde epoch en UTC (`INTEGER`). Las unidades
forman parte del nombre de la columna cuando aplica. Las claves foráneas están activas en cada conexión
(`PRAGMA foreign_keys = ON`).

| Tabla | Campos principales | Integridad |
|---|---|---|
| `trees` | code, species, location, visual_status, notes, latitude, longitude, height_m, trunk_diameter_cm, photos (JSON), created_at, archived_at | `CHECK` de rangos (lat ±90, lng ±180, medidas > 0, código no vacío) |
| `sessions` | tree_id, started_at, ended_at, sampling_hz, calibration (JSON), conditions (JSON), sensors (JSON), status, summary (JSON), notes | FK a trees `RESTRICT`: los árboles se archivan, no se borran. `status` ∈ running/paused/completed/interrupted |
| `samples` | session_id, t, acc_x/y/z (m/s²), lin_x/y/z (m/s²), gyro_x/y/z (rad/s), incl_lateral_deg, incl_frontal_deg | FK a sessions `ON DELETE CASCADE` |
| `inspections` | tree_id, created_at, leaf/trunk/branch/crown_condition, pests, visible_inclination, observations, photos (JSON) | FK a trees |
| `settings` | key, value (JSON) | — |

Decisiones respecto al modelo propuesto:
- `sensorAccuracy` no existe porque `sensors_plus` no expone la precisión del sensor.
- `lin_x/y/z` se añadió porque la aceleración lineal es una medición distinta del acelerómetro.
- `incl_*` se guarda porque depende del estado del filtro y no se puede derivar de una sola muestra.
- `summary` se guarda para dibujar el historial sin recorrer todas las muestras. Es la
  justificación de rendimiento y se puede recalcular desde `samples`.

Para cambiar el esquema, **añade** un paso al final de `kMigrations`. La prueba de migración
comprueba que se aplican solo los pasos pendientes y que los datos se conservan.

## Algoritmo de inclinación

**Sistema de coordenadas (Android):** x hacia la derecha de la pantalla, y hacia la parte
superior y z saliendo de la pantalla hacia el usuario. El acelerómetro mide la aceleración
propia: en reposo y en vertical, y ≈ +9,81 m/s².

**Colocación de referencia:** teléfono en vertical (retrato), con la parte trasera apoyada en el
tronco o en un soporte fijo y la parte superior hacia arriba. La app fija la orientación de pantalla en retrato.

1. **Gravedad estimada**: filtro paso bajo exponencial sobre el acelerómetro,
   `g ← g + α(a − g)` con `α = dt/(τ + dt)` y τ = 0,5 s. Atenúa el temblor de la mano y las
   vibraciones rápidas, y sigue los cambios de inclinación en 1-2 s. Las lecturas no finitas se descartan.
   Todas las lecturas alimentan el filtro, pero solo se guardan a la frecuencia elegida, porque Android
   trata el periodo como una sugerencia y suele entregar más lecturas.
2. **Ángulos (grados)**:
   - Lateral = `atan2(−gx, gy)`. Es positivo cuando la parte superior se inclina a la derecha.
   - Frontal = `atan2(gz, √(gx² + gy²))`. Es positivo cuando la pantalla mira hacia arriba.
   - Desde la vertical = ángulo entre g y el eje y. Si supera 60° la app avisa de que los ejes
     dejan de ser interpretables.
3. **Calibración**: promedio de las lecturas durante 2 s (reduce el ruido en un factor √N). La
   estabilidad se mide con la σ del ángulo de cada lectura respecto al promedio. Si σ > 0,5° se
   recomienda repetir la calibración.
4. **Variación respecto a la referencia**: Δ lateral, Δ frontal y Δ total, que es el ángulo entre los
   vectores de gravedad. Se calcula como `atan2(|a×b|, a·b)`, que es preciso con ángulos pequeños
   y no depende de la orientación.
5. **Inicial y final**: media del primer y del último segundo de la sesión.
6. **Calidad de la medición** (no del árbol). Se marca "Revisar" si:
   - la duración activa es menor de 10 s,
   - llega menos del 80 % de las muestras esperadas,
   - σ de la inclinación es mayor de 1°,
   - la referencia es inestable, o
   - el teléfono no está en vertical.

   Las sesiones interrumpidas se marcan como "Incompleta".

Las diferencias entre sesiones solo son comparables si el teléfono se colocó en el **mismo soporte**.
Por eso la app precarga la colocación anterior y permite reutilizar una referencia.

## Limitaciones

- **Sensores MEMS de consumo**: tienen sesgo (offset) y deriva con la temperatura, una resolución
  típica de 0,01-0,1° en inclinación estática y ruido que aumenta con las vibraciones. Las variaciones
  menores de ~0,2° entre sesiones distintas difícilmente son significativas.
- **Colocación**: el resultado depende por completo de que el teléfono se apoye siempre igual. Sin
  un soporte fijo, la repetibilidad entre días puede ser peor de ±1°.
- **Aceleración y gravedad**: con el teléfono en movimiento, la aceleración lineal contamina la
  estimación de la gravedad. Por eso las sesiones con σ alta se marcan como "Revisar".
- La aceleración lineal y el giroscopio se usan solo si existen. La aceleración lineal es un sensor
  virtual de Android que en algunos teléfonos depende del giroscopio.
- El magnetómetro y el vector de rotación se muestran pero no se usan. No aportan nada a la
  inclinación y el magnetómetro se perturba con metales cercanos.
- No hay monitoreo en segundo plano. Al salir de la app o apagar la pantalla, la sesión se pausa. Durante
  la sesión la pantalla se mantiene encendida, lo que consume batería.
- Las fotos se guardan en la carpeta privada de la app y no se incluyen en la exportación: el JSON
  contiene solo sus rutas. Al quitar una foto de un formulario, su archivo no se borra del disco.
- La sesión en pausa que se reanuda desde el historial estima su tiempo activo anterior
  como nº de muestras / frecuencia.

Guía de pruebas manuales e informe de pruebas: [PRUEBAS.md](PRUEBAS.md).
