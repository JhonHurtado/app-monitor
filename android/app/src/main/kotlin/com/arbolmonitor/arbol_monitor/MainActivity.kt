package com.arbolmonitor.arbol_monitor

import android.hardware.Sensor
import android.hardware.SensorManager
import android.view.WindowManager
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Canal nativo mínimo:
 *  - "sensors": lista real de sensores del dispositivo (SensorManager), para
 *    comprobar disponibilidad antes de medir. sensors_plus no la expone.
 *  - "keepScreenOn": mantiene la pantalla encendida durante una sesión, ya
 *    que la medición se hace con la app abierta (sin servicio en segundo plano).
 *  - "classifyWindow": ejecuta el modelo TFLite sobre 20 muestras del acelerómetro.
 */
class MainActivity : FlutterActivity() {
    private val modelExecutor = Executors.newSingleThreadExecutor()
    private var anomalyInterpreter: Interpreter? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arbol_monitor/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sensors" -> {
                        val sm = getSystemService(SENSOR_SERVICE) as SensorManager
                        result.success(sm.getSensorList(Sensor.TYPE_ALL).map { s ->
                            mapOf(
                                "type" to s.type,
                                "name" to s.name,
                                "vendor" to s.vendor,
                                "resolution" to s.resolution.toDouble(),
                                "maxRange" to s.maximumRange.toDouble(),
                                "minDelayUs" to s.minDelay,
                            )
                        })
                    }
                    "keepScreenOn" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arbol_monitor/model")
            .setMethodCallHandler { call, result ->
                if (call.method != "classifyWindow") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val rawSamples = call.argument<List<*>>("samples")
                if (rawSamples == null || rawSamples.size != 20) {
                    result.error("INVALID_WINDOW", "Se requieren exactamente 20 muestras.", null)
                    return@setMethodCallHandler
                }
                val samples = try {
                    rawSamples.mapIndexed { index, sample ->
                        val axes = sample as? List<*>
                            ?: throw IllegalArgumentException("Muestra $index inválida.")
                        require(axes.size == 3) { "Muestra $index debe tener 3 ejes." }
                        FloatArray(3) { axis ->
                            val value = (axes[axis] as? Number)?.toFloat()
                                ?: throw IllegalArgumentException("Valor no numérico en la muestra $index.")
                            require(value.isFinite()) { "Valor no finito en la muestra $index." }
                            value
                        }
                    }
                } catch (e: IllegalArgumentException) {
                    result.error("INVALID_WINDOW", e.message, null)
                    return@setMethodCallHandler
                }
                modelExecutor.execute {
                    try {
                        val interpreter = anomalyInterpreter ?: Interpreter(
                            modelBuffer(),
                            Interpreter.Options().setNumThreads(2)
                        ).also { anomalyInterpreter = it }
                        val input = arrayOf(samples.toTypedArray())
                        val output = Array(1) { FloatArray(1) }
                        interpreter.run(input, output)
                        result.success(output[0][0].toDouble())
                    } catch (e: Exception) {
                        result.error(
                            "MODEL_INFERENCE_FAILED",
                            e.localizedMessage ?: e.javaClass.simpleName,
                            null
                        )
                    }
                }
            }
    }

    private fun modelBuffer(): ByteBuffer {
        val bytes = assets.open("centinela_forestal.tflite").use { it.readBytes() }
        return ByteBuffer.allocateDirect(bytes.size)
            .order(ByteOrder.nativeOrder())
            .apply {
                put(bytes)
                rewind()
            }
    }

    override fun onDestroy() {
        modelExecutor.execute {
            anomalyInterpreter?.close()
            anomalyInterpreter = null
        }
        modelExecutor.shutdown()
        super.onDestroy()
    }
}
