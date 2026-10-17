# Pruebas

## 1. Pruebas automatizadas

```bash
flutter test
```

Las pruebas usan una base SQLite en memoria (`sqflite_common_ffi`) y flujos de sensores
simulados. Validan la **lógica**, no el hardware: los sensores físicos deben probarse en un
teléfono real (sección 2).

| Archivo | Qué cubre |
|---|---|
| `test/tilt_test.dart` | Conversión grados/radianes. Inclinación lateral y frontal con ángulos conocidos. Teléfono fuera de eje. Ida y vuelta ángulos ↔ vector. Precisión con ángulos pequeños. Filtro de gravedad (convergencia, ruido, lecturas inválidas). Calibración (promedio, estabilidad, lecturas insuficientes, JSON). Formato con coma decimal y sin "-0". |
| `test/summary_test.dart` | Estadísticas (min, max, media, σ). Resumen de sesión (inicial/final, Δ respecto a la referencia, magnitudes). Calidad (sesión corta, con huecos, inestable, interrumpida, vacía). Eventos de movimiento. JSON. Alertas: desactivadas por defecto, mensajes descriptivos sin conclusiones, umbrales y comparación entre sesiones. |
| `test/db_test.dart` | CRUD, búsqueda y archivado de árboles. Restricciones `CHECK`. Claves foráneas activas (`RESTRICT` y `CASCADE`). Persistencia por lotes y cierre con resumen. Filtros por árbol, fechas e incompletas. Recuperación de sesiones interrumpidas. Fechas en ms epoch. Inspecciones. Ajustes. Migraciones (base nueva, y actualización que conserva datos). |
| `test/export_test.dart` | CSV de sesiones (cabeceras con unidades, escape de comas, comillas y saltos de línea, ISO 8601 UTC). CSV de muestras (vacíos para sensores ausentes). JSON (estructura, unidades, campos JSON decodificados). |
| `test/recorder_test.dart` | Grabación con escritura por lotes. Almacenamiento a la frecuencia elegida aunque el sensor entregue más rápido. Δ respecto a la referencia en vivo. Pausa con liberación de sensores y reanudación. Salir sin finalizar deja la sesión en pausa. Error del acelerómetro (`NO_SENSOR`) pausa sin perder datos. Sensores opcionales ausentes. Lecturas inválidas. Calibración. |
| `test/widgets_test.dart` | Navegación de las 4 pestañas con estados vacíos. Alta de árbol con validación. Sensores no disponibles bloquean la medición. Flujo completo calibrar → medir → pausar → reanudar → finalizar. Borrado con confirmación. Umbrales vacíos por defecto y validados. |

## 2. Guía de pruebas manuales en un teléfono Android real

Prepara un soporte fijo (por ejemplo, una abrazadera o una tabla atada al tronco, o un borde de
mesa para las pruebas de banco) y, si es posible, un nivel de burbuja o una app de inclinómetro de referencia.

### A. Sensores
1. Abre **Monitoreo**. Comprueba que la lista indica "Disponible" o "No disponible" para cada sensor
   y que coincide con la ficha técnica del teléfono.
2. Abre **Ver lecturas en vivo**:
   - Con el teléfono quieto y en vertical, el acelerómetro da y ≈ 9,8 m/s², la aceleración lineal ≈ 0
     y el giroscopio ≈ 0.
   - Gira el teléfono: el giroscopio debe cambiar de signo según el sentido del giro.
3. Pon la app en segundo plano y vuelve: las lecturas se reanudan. Con un monitor de batería se
   puede comprobar que los sensores se detienen al salir.

### B. Exactitud de la inclinación (banco de pruebas)
1. Apoya el teléfono en vertical contra una superficie que hayas verificado con un nivel. Calibra.
2. Inclínalo lateralmente con cuñas de ángulo conocido (por ejemplo 2° y 5°). El Δ lateral debe
   coincidir dentro de ±0,3°. Repite en el eje frontal.
3. Vuelve a la posición inicial: el Δ debe volver a ≈ 0 (repetibilidad).
4. Sostén el teléfono con la mano: la sesión debe marcarse como "Revisar" (σ > 1°).

### C. Sesión completa en un árbol
1. Registra un árbol con GPS y una foto. Comprueba que se pide el permiso de ubicación solo al pulsar el botón.
2. Inicia una sesión: indica la colocación y el viento y calibra con el teléfono en el soporte.
3. Mide 1-2 minutos. Pausa 10 s, reanuda y finaliza con una nota.
4. En el detalle comprueba la duración, las muestras recibidas frente a las esperadas, la referencia, las estadísticas, la gráfica y la calidad.
5. Repite otro día con **"Reutilizar la referencia de una sesión anterior"** y el mismo soporte.
   Compara ambas sesiones en **Historial › Comparar**.

### D. Interrupciones
1. Durante una sesión, pulsa Inicio de Android: la sesión pasa a "En pausa" y los datos se conservan.
2. Durante una sesión, cierra la app desde Recientes. Al reabrirla, la sesión aparece como
   "Incompleta" con las muestras hasta el último lote (máximo ~1 s perdido).
3. Pulsa Atrás durante una sesión: debe pedir confirmación y dejarla en pausa. Reanúdala desde el historial.
4. Comprueba que la pantalla no se apaga durante la sesión y que vuelve a apagarse con normalidad después.

### E. Historial, alertas y exportación
1. Filtra por árbol y por rango de fechas, y activa "Solo incompletas".
2. En **Inicio › ⚙**, define un umbral de variación (por ejemplo 0,5°). Mide inclinando el soporte y
   comprueba que el mensaje describe el dato sin hacer interpretaciones. Vacía el campo y la alerta debe desaparecer.
   Durante una sesión en vivo, supera el umbral operativo de 15° respecto a la calibración:
   debe aparecer el aviso visual y sonar una vez al cruzarlo. Vuelve por debajo y supéralo
   de nuevo para verificar que el sonido se repite solo en el nuevo cruce. El volumen del
   dispositivo debe estar habilitado.
3. Exporta y comparte por correo o guarda en Drive. Abre `sesiones.csv` en una hoja de cálculo y
   `datos.json` en un editor. Comprueba las unidades y que el número de filas de `muestras.csv` coincide con el de muestras.
4. Elimina una sesión: debe pedir confirmación y desaparecer junto con sus muestras.

### F. Inspecciones
1. Crea dos inspecciones con fotos en fechas distintas y edita una.
2. Usa **Comparar**: los campos que cambiaron deben quedar resaltados.

### G. Persistencia
Reinicia el teléfono y comprueba que los árboles, las sesiones, las inspecciones y los ajustes siguen ahí.

## 3. Informe de la última ejecución

Fecha: 16/10/2026 · Flutter 3.41.6 · Dart 3.11.4 · macOS (arm64)

| Verificación | Resultado |
|---|---|
| `flutter analyze` | Sin problemas |
| `flutter test` | 53 pruebas superadas, 0 fallidas |
| `flutter build apk --debug` | Correcto: `app-debug.apk` (160 MB) |
| `flutter build apk --release --split-per-abi` | Correcto: arm64-v8a 20,3 MB, armeabi-v7a 17,8 MB, x86_64 21,7 MB |
| Pruebas en un teléfono físico | **No realizadas**: no había ningún dispositivo conectado en el entorno de desarrollo. Usa la guía de la sección 2. |

Errores encontrados y corregidos gracias a las pruebas:
- `Loader` devolvía un `Future` dentro de `setState`, lo que hacía fallar la recarga tras cada escritura.
- La pantalla de lecturas en vivo se redibujaba cada 150 ms aunque no hubiera datos nuevos (consumo innecesario).
- La referencia se mostraba como "-0,00°" por el cero negativo.
- Android entrega a menudo más lecturas que las pedidas. Ahora se guardan a la frecuencia elegida y el filtro sigue usando todas.

### Pendiente / fuera del alcance del MVP
- Validación de exactitud y repetibilidad en teléfonos reales (sección 2B).
- Firma de release con una clave propia.
- Incluir las fotos en la exportación (ahora solo se exportan sus rutas) y limpiar las fotos huérfanas.
- Usar el sensor de gravedad nativo (`TYPE_GRAVITY`) cuando exista, como alternativa al filtro paso bajo.
- Selección de varias colocaciones de referencia, por ejemplo con el teléfono plano sobre un corte horizontal.
